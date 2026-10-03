import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { supabase } from '../config/supabase.js';
import { intakeQueue } from '../workers/queueManager.js';
import { 
  generateCounselorResponse, 
  CRITICAL_SELF_HARM_REGEX, 
  RELIEF_HARDSHIP_REGEX, 
  TICKET_CONFIRM_REGEX 
} from '../services/crisisCounselorService.js';
import { getIO } from '../services/socketManager.js';
import { evaluateLifeSafety } from '../services/safetyGuardrails.js';
import { classifyCategoryDynamic } from '../utils/categoryClassifier.js';
import { GoogleGenerativeAI } from '@google/generative-ai';
import { PharmacyDbService } from '../modules/pharmacy/pharmacyDbService.js';
import { PatientClinicalRagService } from '../services/patientClinicalRagService.js';

const chatRouter = Router();


const ChatMessageSchema = z.object({
  ticketId: z.string().uuid().optional().nullable(),
  studentPhone: z.string().optional().nullable().default('web-client'),
  studentName: z.string().optional().nullable().default('Anonymous'),
  message: z.string().min(1, 'Message cannot be empty'),
  contextMessage: z.string().optional().nullable(),
  history: z.array(z.object({ sender: z.string(), message: z.string() })).optional().nullable(),
  confirmTicket: z.boolean().optional().nullable(),
  institutionId: z.string().optional().nullable(),
  media_url: z.string().optional().nullable(),
  attachment_url: z.string().optional().nullable(),
  mediaUrl: z.string().optional().nullable(),
  attachmentUrl: z.string().optional().nullable(),
});

// ─── POST /api/v1/chat/message ───────────────────────────────────
chatRouter.post('/message', async (req: Request, res: Response) => {
  try {
    const institutionId = (req.headers['x-institution-id'] as string) || req.body.institutionId || 'edu-admin-123';
    const parsed = ChatMessageSchema.parse(req.body);

    let mediaUrl = parsed.media_url || parsed.attachment_url || parsed.mediaUrl || parsed.attachmentUrl || req.body.media_url || req.body.attachment_url || req.body.receipt_url || null;

    if (mediaUrl && mediaUrl.startsWith('data:')) {
      try {
        const commaIdx = mediaUrl.indexOf(',');
        const base64Data = commaIdx !== -1 ? mediaUrl.substring(commaIdx + 1) : mediaUrl;
        const mimeMatch = mediaUrl.match(/data:([^;]+);/);
        const mimeType = mimeMatch ? mimeMatch[1] : 'application/pdf';
        const ext = mimeType.includes('pdf') ? 'pdf' : (mimeType.includes('png') ? 'png' : 'jpg');
        const fileName = `chat_${Date.now()}_${Math.random().toString(36).substring(7)}.${ext}`;
        const buffer = Buffer.from(base64Data, 'base64');

        const { error: uploadError } = await supabase.storage.from('receipts').upload(fileName, buffer, {
          contentType: mimeType,
          upsert: true
        });

        if (!uploadError) {
          const { data: { publicUrl } } = supabase.storage.from('receipts').getPublicUrl(fileName);
          mediaUrl = publicUrl;
          console.log(`☁️ [Supabase Storage] Saved chat attachment to receipts bucket: ${publicUrl}`);
        }
      } catch (uploadErr: any) {
        console.warn(`⚠️ [Supabase Storage] Chat base64 upload notice: ${uploadErr.message}`);
      }
    }

    let activeTicketId: string | null = parsed.ticketId || null;
    let isNewTicketCreated = false;
    let triageJobId: string | null = null;

    const isLifeSafety = CRITICAL_SELF_HARM_REGEX.test(parsed.message);
    const isExplicitConfirmation = parsed.confirmTicket === true || TICKET_CONFIRM_REGEX.test(parsed.message.trim());
    const isHardshipInquiry = RELIEF_HARDSHIP_REGEX.test(parsed.message);

    let effectiveMessage = parsed.message;
    if (isExplicitConfirmation) {
      if (parsed.contextMessage) {
        effectiveMessage = `${parsed.contextMessage}\n\n[Confirmation: ${parsed.message}]`;
      } else if (parsed.history && parsed.history.length > 0) {
        const priorUserMsgs = parsed.history.filter(h => h.sender.toUpperCase() === 'STUDENT' && h.message !== parsed.message);
        const lastPrior = priorUserMsgs.pop();
        if (lastPrior) {
          effectiveMessage = `${lastPrior.message}\n\n[Confirmation: ${parsed.message}]`;
        }
      }
    }

    const shouldCreateTicket = !activeTicketId && (isLifeSafety || isExplicitConfirmation);

    if (shouldCreateTicket) {
      const lifeSafety = evaluateLifeSafety(effectiveMessage);
      const initialCategory = lifeSafety.isLifeSafetyCritical
        ? lifeSafety.lockedCategory
        : await classifyCategoryDynamic(effectiveMessage);
      const initialUrgency = lifeSafety.isLifeSafetyCritical ? 'Critical' : (isHardshipInquiry || RELIEF_HARDSHIP_REGEX.test(effectiveMessage) ? 'High' : 'Routine');

      const { data: ticket, error: ticketErr } = await supabase
        .from('tickets')
        .insert([
          {
            institution_id: institutionId,
            student_phone: parsed.studentPhone,
            raw_message: effectiveMessage,
            media_url: mediaUrl,
            parsed_category: initialCategory,
            urgency_level: initialUrgency,
            status: 'Pending'
          }
        ])
        .select()
        .single();

      if (ticketErr) {
        console.error('[ChatRouter] Ticket creation error:', ticketErr);
        throw new Error(`Failed to create ticket for chat: ${ticketErr.message}`);
      }

      activeTicketId = ticket.id;
      isNewTicketCreated = true;

      try {
        const triageJob = await intakeQueue.add(
          'process-chat-triage',
          {
            ticketId: activeTicketId,
            rawMessage: effectiveMessage,
            mediaUrl: mediaUrl,
            media_url: mediaUrl,
            attachmentUrl: mediaUrl,
            studentName: parsed.studentName,
            studentPhone: parsed.studentPhone,
            institutionId,
            source: 'chat'
          },
          {
            attempts: 3,
            backoff: { type: 'exponential', delay: 2000 }
          }
        );
        triageJobId = triageJob.id ? String(triageJob.id) : null;
      } catch (queueErr) {
        console.warn('[ChatRouter] BullMQ queue dispatch warning:', queueErr);
      }
    }

    if (activeTicketId) {
      try {
        await supabase.from('ticket_messages').insert([
          {
            ticket_id: activeTicketId,
            sender: 'STUDENT',
            message: parsed.message,
            is_crisis_response: isLifeSafety
          }
        ]);
      } catch (msgInsertErr) {
        console.warn('[ChatRouter] Warning inserting student message:', msgInsertErr);
      }
    }

    let history: Array<{ sender: string; message: string }> = [];
    if (activeTicketId) {
      try {
        const { data: historyData } = await supabase
          .from('ticket_messages')
          .select('sender, message')
          .eq('ticket_id', activeTicketId)
          .order('created_at', { ascending: true })
          .limit(10);

        if (historyData) {
          history = historyData.map((h) => ({ sender: h.sender, message: h.message }));
        }
      } catch (histErr) {
        console.warn('[ChatRouter] History fetch warning:', histErr);
      }
    }

    const counselorResponse = await generateCounselorResponse(
      activeTicketId,
      parsed.message,
      history,
      { isTicketCreated: isNewTicketCreated }
    );

    if (activeTicketId) {
      try {
        const io = getIO();
        io.to(`ticket:${activeTicketId}`).emit('chat:new_message', {
          ticketId: activeTicketId,
          sender: 'COUNSELOR_AI',
          message: counselorResponse.reply,
          isCrisisResponse: counselorResponse.isCrisisResponse,
          resources: counselorResponse.resources,
          timestamp: new Date().toISOString()
        });
      } catch (socketErr) {
        console.warn('[ChatRouter] Socket emit notice:', socketErr);
      }
    }

    res.status(200).json({
      success: true,
      ticketId: activeTicketId,
      jobId: triageJobId,
      reply: counselorResponse.reply,
      isCrisisResponse: counselorResponse.isCrisisResponse,
      requiresConfirmation: counselorResponse.requiresConfirmation,
      isTicketLogged: counselorResponse.isTicketLogged,
      resources: counselorResponse.resources,
      latencyMs: counselorResponse.latencyMs
    });
  } catch (error: any) {
    if (error instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation failed', details: error.issues });
      return;
    }
    console.error('[ChatRouter] Error processing chat message:', error);
    res.status(500).json({ error: error.message || 'Internal server error' });
  }
});

// ─── GET /api/v1/chat/messages/:ticketId ─────────────────────────
chatRouter.get('/messages/:ticketId', async (req: Request, res: Response) => {
  try {
    const { ticketId } = req.params;
    const { data: messages, error } = await supabase
      .from('ticket_messages')
      .select('*')
      .eq('ticket_id', ticketId)
      .order('created_at', { ascending: true });

    if (error) throw error;

    res.status(200).json({
      success: true,
      ticketId,
      messages: messages || []
    });
  } catch (error: any) {
    console.error('[ChatRouter] Error fetching ticket messages:', error);
    res.status(500).json({ error: error.message || 'Failed to fetch messages' });
  }
});

import { ChatController } from '../controllers/chatController.js';

// ─── POST /api/v1/chat/claims/:id/messages ───────────────────────
chatRouter.post('/claims/:id/messages', ChatController.sendClaimMessage);

// ─── GET /api/v1/chat/claims/:id/messages ────────────────────────
chatRouter.get('/claims/:id/messages', ChatController.getClaimMessages);

// ─────────────────────────────────────────────────────────────────
// POST /api/v1/chat/mental-health
// Gemini-powered mental health counselor chat with live patient data
// ─────────────────────────────────────────────────────────────────
const genAIForCounselor = new GoogleGenerativeAI(process.env.GEMINI_API_KEY || '');

const MENTAL_HEALTH_SYSTEM_PROMPT = `You are Aria, a compassionate, clinically-informed mental health counselor and health companion embedded within the MedAccess Campus Health platform.

Your personality and approach:
- You are warm, empathetic, non-judgmental, and genuinely caring — like a real therapist who truly listens.
- Practice active listening: reflect back what the patient says, validate their feelings, and ask thoughtful follow-up questions.
- Use a conversational, human tone — never robotic, never overly clinical. Speak like a caring friend who also happens to have clinical training.
- Do NOT give one-liner responses. Every response should feel like a real conversation: 3 to 6 sentences, flowing naturally.
- Ask one meaningful follow-up question at the end of your response to deepen the conversation — unless it's a crisis or a farewell.

Live Clinical Dossier & Health Screenings (RAG Access):
- You have direct, real-time access to the patient's records provided in [CLINICAL PATIENT DOSSIER]. This includes their latest health screenings, physical symptoms, vital signs, CDSS diagnostic evaluations, active medications, allergies, and emergency claims.
- When the patient asks about their health screening, test results, physical health, or diagnoses:
  * Acknowledge that you see their latest health screening record directly.
  * Translate their primary clinical condition, reported symptoms, and key vitals (like heart rate, SpO2, blood pressure) into warm, reassuring, layperson-friendly terms.
  * Validate any emotional distress, anxiety, or worry they feel about these physical symptoms.
  * Remind them that while this AI screening provides immediate insights, discussing it with their attending campus doctor or visiting the campus health center is the safest next step.
- If the patient mentions their medications, allergies, or financial claims, reference the data in [CLINICAL PATIENT DOSSIER] to provide deeply personalized care.

Crisis handling (MANDATORY):
- If the patient mentions suicidal thoughts, self-harm, wanting to die, or any acute danger: express deep care immediately. Do NOT ask follow-up questions in a crisis. Urge them to call Tele-MANAS (14416) or 988 right now. Say they are not alone and that you care deeply about their safety.

Boundaries:
- You support, guide, explain, and validate — you do not replace their primary physician or emergency room.
- Always maintain professional boundaries while being deeply human.

Format: Natural, flowing prose only. No markdown headers. No bullet points. No numbered lists. Just a warm, real conversation.`;

const MentalHealthSchema = z.object({
  patientId: z.string().min(1),
  message: z.string().min(1),
  history: z
    .array(z.object({ role: z.enum(['user', 'model']), text: z.string() }))
    .optional()
    .default([]),
});

chatRouter.post('/mental-health', async (req: Request, res: Response) => {
  try {
    const { patientId, message, history } = MentalHealthSchema.parse(req.body);

    const isCrisis = CRITICAL_SELF_HARM_REGEX.test(message);

    // Multi-entity Clinical Patient RAG Retrieval
    let patientContextBlock = '';
    let ragContext: any = null;
    try {
      ragContext = await PatientClinicalRagService.retrievePatientContext(patientId);
      patientContextBlock = PatientClinicalRagService.formatRagContextForPrompt(ragContext, 'MENTAL_HEALTH');
      console.log(`📋 [MentalHealthChat] RAG context retrieved for patient "${patientId}": ${ragContext.screenings.length} screenings, ${ragContext.medications.length} meds, ${ragContext.allergies.length} allergies`);
    } catch (ragErr) {
      console.warn('[MentalHealthChat] RAG retrieval notice:', ragErr);
    }

    const systemWithContext = `${MENTAL_HEALTH_SYSTEM_PROMPT}\n\n${patientContextBlock}`;

    let reply = '';


    if (!process.env.GEMINI_API_KEY) {
      reply = isCrisis
        ? 'I can hear how much pain you are in right now, and I want you to know that you are not alone. Please reach out to Tele-MANAS right now by calling 14416 — their counselors are available 24 hours a day and they truly care. I am here with you.'
        : 'I am really glad you reached out today. It takes a lot of courage to share what you are going through, and I want you to know that everything you are feeling makes complete sense. Would you like to tell me a bit more about what has been on your mind lately?';
    } else {
      try {
        const model = genAIForCounselor.getGenerativeModel({
          model: 'gemini-3.5-flash-lite',
          systemInstruction: systemWithContext,
          generationConfig: {
            maxOutputTokens: 400,
            temperature: 0.88,
            topP: 0.94,
          },
        });

        const chatHistory = history.map(h => ({
          role: h.role,
          parts: [{ text: h.text }],
        }));

        const chat = model.startChat({ history: chatHistory });
        const result = await chat.sendMessage(message);
        reply = result.response.text().trim();

        if (!reply || reply.length < 20) throw new Error('Empty model response');
      } catch (geminiErr: any) {
        console.warn('[MentalHealthChat] Gemini error, using empathetic fallback:', geminiErr?.message);
        reply = isCrisis
          ? 'I can hear how much pain you are in right now, and I want you to know that you are not alone in this. Please call Tele-MANAS at 14416 or 988 right now — a real counselor is ready to talk with you and they care deeply about your safety.'
          : 'I really hear you, and I am glad you are here talking to me. What you are feeling is completely valid, and you deserve support. Can you share a bit more about what has been weighing on you the most?';
      }
    }

    console.log(`🧠 [MentalHealthChat] Patient ${patientId} | Crisis: ${isCrisis} | Reply: ${reply.length} chars`);

    const suggestedActions: Array<{ title: string; action: string; payload?: any }> = [];
    if (ragContext?.screenings && ragContext.screenings.length > 0) {
      const s = ragContext.screenings[0];
      suggestedActions.push({
        title: `View Screening Report (${s.primaryDiagnosis || s.riskLevel || 'Recent'})`,
        action: 'OPEN_SCREENING',
        payload: { screeningId: s.id }
      });
    }
    if (ragContext?.medications && ragContext.medications.length > 0) {
      suggestedActions.push({
        title: 'Check Active Prescriptions',
        action: 'OPEN_PHARMACY',
      });
    }

    res.status(200).json({
      success: true,
      reply,
      isCrisis,
      suggestedActions,
      screeningContextPresent: (ragContext?.screenings?.length ?? 0) > 0,
      resources: isCrisis
        ? [
            { name: 'Tele-MANAS (Govt of India)', number: '14416', actionUrl: 'tel:14416' },
            { name: '988 Suicide & Crisis Lifeline', number: '988', actionUrl: 'tel:988' },
            { name: 'Vandrevala Helpline', number: '+91 9999 666 555', actionUrl: 'tel:+919999666555' },
          ]
        : null,
    });
  } catch (err: any) {
    if (err instanceof z.ZodError) {
      res.status(400).json({ error: 'Validation failed', details: err.issues });
      return;
    }
    console.error('[MentalHealthChat] Error:', err);
    res.status(500).json({ error: err.message || 'Internal server error' });
  }
});

export default chatRouter;
