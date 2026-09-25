import { pipeline } from '@xenova/transformers';
import { supabase } from '../config/supabase.js';

let counselorModel: any = null;
let isModelLoading = false;
let hasAttemptedInit = false;

/**
 * Initializes or returns the cached local ONNX text-generation pipeline.
 * Uses quantized Qwen Chat for lightweight, fast CPU execution.
 */
export async function getCounselorPipeline() {
  if (!counselorModel && !isModelLoading && !hasAttemptedInit) {
    isModelLoading = true;
    hasAttemptedInit = true;
    try {
      console.log('🤖 [Local Counselor AI] Initializing local text-generation pipeline (Xenova/Qwen1.5-0.5B-Chat)...');
      counselorModel = await pipeline(
        'text-generation',
        'Xenova/Qwen1.5-0.5B-Chat',
        { quantized: true } as any
      );
      console.log('✅ [Local Counselor AI] Qwen Chat pipeline loaded successfully.');
    } catch (err: any) {
      try {
        console.log('🤖 [Local Counselor AI] Trying onnx-community/Qwen2.5-0.5B-Instruct fallback...');
        counselorModel = await pipeline(
          'text-generation',
          'onnx-community/Qwen2.5-0.5B-Instruct',
          { quantized: true } as any
        );
      } catch (fbErr) {
        console.log('ℹ️ [Local Counselor AI] Local model offline, using Rogerian PFA counseling engine.');
        counselorModel = null;
      }
    } finally {
      isModelLoading = false;
    }
  }
  return counselorModel;
}

export const CRITICAL_SELF_HARM_REGEX = /\b(suicid(e|al)|kill myself|end my life|self harm|hurt myself|want to die|overdose|cut myself|hang myself|don't want to live|no reason to live|end it all|better off dead|give up on life)\b/i;

export const RELIEF_HARDSHIP_REGEX = /\b(rent|evict|eviction|landlord|homeless|housing|food|hungry|groceries|tuition|fee|fees|medical bill|hospital|medicine|prescription|urgent grant|need money|financial hardship|\$\d+|\u20B9\d+)\b/i;

export const TICKET_CONFIRM_REGEX = /^(yes|yes please|please submit|submit ticket|submit grant|confirm|go ahead|create ticket|open ticket|please help me apply|yes open ticket)\b/i;

/**
 * Diagnostic summary context produced by the Multimodal Fusion & Vision screening engine.
 */
export interface DiagnosticSummaryContext {
  riskTier: string; // e.g. "Moderate Need" | "Critical Referral" | "Low Risk"
  riskScore: number; // e.g. 0.72
  uncertainty: string; // e.g. "±0.03"
  topFeatures: string[]; // e.g. ["High Pain Scale", "Localized Skin Rash"]
  heatMapGenerated: boolean;
  primaryDiagnosis?: string;
  differentialDiagnoses?: Array<{ condition: string; probability: number }>;
  clinicalRecommendations?: string[];
  patientNotes?: string;
}

export const MANDATORY_DISCLAIMER = 'This is an AI-assisted screening tool, not a final medical diagnosis.';

/**
 * Builds ChatML prompt for Qwen2.5 to explain screening findings in empathetic, plain language.
 */
export function buildDiagnosticInterpretationPrompt(
  context: DiagnosticSummaryContext,
  patientQuery?: string
): { system: string; user: string } {
  const isCritical =
    context.riskTier.toLowerCase().includes('critical') ||
    context.riskScore >= 0.75;
  const isModerate =
    !isCritical &&
    (context.riskTier.toLowerCase().includes('moderate') || context.riskScore >= 0.40);

  const riskPercent = Math.round(context.riskScore * 100);
  const featureList = context.topFeatures && context.topFeatures.length > 0
    ? context.topFeatures.join(', ')
    : 'Clinical symptom presentation';

  const system = `You are MedAccess's Clinical Interpretation & First Aid Assistant.
Your role is to explain clinical health screening results in empathetic, clear, patient-friendly language.
CRITICAL CLINICAL RULES:
1. Explain the diagnostic finding (${context.primaryDiagnosis || context.riskTier}) and salient features (${featureList}) in warm, plain language.
2. Mandatory Disclaimer: You MUST explicitly include this exact phrase: "${MANDATORY_DISCLAIMER}"
3. Actionable Next Steps:
   ${
     isCritical
       ? '- The assessment is CRITICAL. You must strongly urge the patient to proceed to the Emergency Room (ER) or call emergency services immediately.'
       : isModerate
       ? '- The assessment indicates MODERATE NEED. Advise scheduling a clinic or telemedicine consultation within 24-48 hours. Suggest comfort measures such as applying a cool compress, staying hydrated, and resting.'
       : '- The assessment indicates LOW RISK. Reassure the patient, advise gentle monitoring for 7 days, and suggest routine clinical follow-up if symptoms persist.'
   }
4. Address the patient's emotional distress or worry with Psychological First Aid (grounding, reassurance, active validation). Keep responses concise (3-5 sentences).`;

  const user = patientQuery
    ? `Patient query: "${patientQuery}". Diagnostic context: Risk Score ${riskPercent}% (${context.riskTier}, uncertainty ${context.uncertainty}), primary finding: "${context.primaryDiagnosis || 'Symptom cluster'}", salient features: ${featureList}, Grad-CAM visual heatmap: ${context.heatMapGenerated ? 'Generated' : 'None'}. Please explain and advise.`
    : `Please interpret my screening result. Risk Score: ${riskPercent}% (${context.riskTier}, uncertainty ${context.uncertainty}). Salient features: ${featureList}. Grad-CAM heatmap generated: ${context.heatMapGenerated}. What does this mean and what should I do next?`;

  return { system, user };
}

/**
 * Psychological First Aid deterministic interpretation engine ensuring 100% compliance with
 * mandatory clinical disclaimers and risk-tiered next steps.
 */
export function generateRogerianDiagnosticInterpretation(
  context: DiagnosticSummaryContext,
  patientQuery?: string
): string {
  const isCritical =
    context.riskTier.toLowerCase().includes('critical') ||
    context.riskScore >= 0.75;
  const isModerate =
    !isCritical &&
    (context.riskTier.toLowerCase().includes('moderate') || context.riskScore >= 0.40);

  const riskPercent = Math.round(context.riskScore * 100);
  const condition = context.primaryDiagnosis || (isCritical ? 'Acute Clinical Presentation' : isModerate ? 'Mild-to-Moderate Inflammation' : 'Localized Benign Condition');
  const features = context.topFeatures.length > 0 ? context.topFeatures.slice(0, 3).join(' and ') : 'your reported symptoms';

  let interpretation = '';
  let nextSteps = '';

  if (isCritical) {
    interpretation = `I can see why this is concerning—your screening identified significant clinical indicators for ${condition}, driven primarily by ${features} (Risk Score: ${riskPercent}% ${context.uncertainty}).`;
    nextSteps = `Because of the critical urgency level, please proceed to the Emergency Room (ER) immediately or contact local emergency services. Do not drive yourself if experiencing dizziness or severe pain.`;
  } else if (isModerate) {
    interpretation = `Thank you for checking in. Your screening indicates moderate clinical attention for ${condition}, influenced primarily by ${features} (Risk Score: ${riskPercent}% ${context.uncertainty}).${context.heatMapGenerated ? ' Our visual attention heatmap highlighted localized inflammation in the symptom area.' : ''}`;
    nextSteps = `We recommend that you schedule a clinic consultation within 48 hours for an in-person evaluation. In the meantime, apply a clean cold compress to soothe the area, stay well hydrated, and rest.`;
  } else {
    interpretation = `Your screening reflects a low risk level (Score: ${riskPercent}% ${context.uncertainty}) consistent with a mild, self-limiting presentation of ${condition}.`;
    nextSteps = `Continue gentle monitoring over the next few days, keep the area clean and protected, and consult a healthcare provider if symptoms worsen or persist beyond 7 days.`;
  }

  let queryResponse = '';
  if (patientQuery) {
    const qLower = patientQuery.toLowerCase();
    if (qLower.includes('contagious') || qLower.includes('spread')) {
      queryResponse = `Regarding your question about contagion: avoid sharing personal towels or touching the affected area until a clinician evaluates it.`;
    } else if (qLower.includes('pain') || qLower.includes('hurt') || qLower.includes('compress')) {
      queryResponse = `To manage discomfort, applying a cool damp cloth for 10-15 minutes can provide soothing relief.`;
    } else if (qLower.includes('scared') || qLower.includes('worried') || qLower.includes('anxious')) {
      queryResponse = `It is completely natural to feel anxious when health concerns arise. Take a slow, steady breath with me—you have taken the right first step by screening early.`;
    }
  }

  const parts = [interpretation];
  if (queryResponse) parts.push(queryResponse);
  parts.push(`Recommended Next Steps: ${nextSteps}`);
  parts.push(`Disclaimer: ${MANDATORY_DISCLAIMER}`);

  return parts.join('\n\n');
}

/**
 * Interprets clinical screening results with local ONNX Qwen2.5 or Rogerian PFA engine.
 */
export async function interpretDiagnosticResult(
  context: DiagnosticSummaryContext,
  patientQuery?: string,
  history: Array<{ sender: string; message: string }> = []
): Promise<CounselorResponseResult> {
  const startTime = Date.now();
  const isCritical =
    context.riskTier.toLowerCase().includes('critical') ||
    context.riskScore >= 0.75;
  const suggestedResources = isCritical ? EMERGENCY_RESOURCES : null;

  let reply = '';
  try {
    const generator = await getCounselorPipeline();
    if (generator) {
      const { system, user } = buildDiagnosticInterpretationPrompt(context, patientQuery);
      const messages = [
        { role: 'system', content: system },
        ...history.slice(-4).map((msg) => ({
          role: msg.sender === 'PATIENT' || msg.sender === 'USER' ? 'user' : 'assistant',
          content: msg.message
        })),
        { role: 'user', content: user }
      ];

      const genPromise = generator(messages, {
        max_new_tokens: 120,
        temperature: 0.6,
        top_p: 0.85,
        do_sample: true
      });

      const timeoutPromise = new Promise((_, reject) =>
        setTimeout(() => reject(new Error('Inference timeout')), 3000)
      );

      const output: any = await Promise.race([genPromise, timeoutPromise]);
      if (Array.isArray(output) && output.length > 0) {
        const genText = output[0]?.generated_text;
        if (Array.isArray(genText)) {
          const lastMsg = genText.at(-1);
          reply = lastMsg?.content?.trim() || '';
        } else if (typeof genText === 'string') {
          reply = genText.replace(/<\|.*?\|>/g, '').trim();
          if (reply.includes('assistant\n')) {
            reply = reply.split('assistant\n').pop()?.trim() || reply;
          }
        }
      }
    }
  } catch (_) {
    // Seamless fallback to Rogerian clinical interpretation
  }

  // Fallback if model output is empty or too short
  if (!reply || reply.length < 30) {
    reply = generateRogerianDiagnosticInterpretation(context, patientQuery);
  }

  // Ensure mandatory disclaimer is ALWAYS present
  if (!reply.includes(MANDATORY_DISCLAIMER)) {
    reply += `\n\nDisclaimer: ${MANDATORY_DISCLAIMER}`;
  }

  // Address specific patient query topics if not already addressed in model output
  if (patientQuery) {
    const qLower = patientQuery.toLowerCase();
    const rLower = reply.toLowerCase();
    if ((qLower.includes('contagious') || qLower.includes('spread')) &&
        !rLower.includes('contag') && !rLower.includes('towels')) {
      reply += '\n\nRegarding contagion: Keep the area covered, avoid scratching, and avoid sharing personal towels until evaluated by a healthcare professional.';
    } else if ((qLower.includes('pain') || qLower.includes('hurt') || qLower.includes('compress')) &&
        !rLower.includes('compress') && !rLower.includes('cloth')) {
      reply += '\n\nTo manage discomfort: Applying a clean, cool damp compress for 10-15 minutes can provide soothing relief.';
    }
  }

  // Ensure next steps are present if model missed them
  if (isCritical && !reply.toLowerCase().includes('emergency') && !reply.toLowerCase().includes('er')) {
    reply += '\n\nUrgent Action: Please proceed to the ER immediately or call local emergency services.';
  }

  const latencyMs = Date.now() - startTime;

  return {
    reply,
    isCrisisResponse: isCritical,
    requiresConfirmation: false,
    isTicketLogged: false,
    resources: suggestedResources,
    latencyMs
  };
}

export interface EmergencyResourceCard {
  name: string;
  number: string;
  category: string;
  actionUrl: string;
  description: string;
  icon: string;
}

export const EMERGENCY_RESOURCES: EmergencyResourceCard[] = [
  {
    name: "Tele-MANAS (Govt of India)",
    number: "14416",
    category: "Mental Health & Suicide Prevention",
    actionUrl: "tel:14416",
    description: "Toll-free 24/7 National Tele-Mental Health Programme (or 1800-891-4416).",
    icon: "support_agent"
  },
  {
    name: "988 Suicide & Crisis Lifeline",
    number: "988",
    category: "Immediate Emergency Lifeline",
    actionUrl: "tel:988",
    description: "24/7 confidential clinical support for people in suicidal crisis or severe psychiatric distress.",
    icon: "crisis_alert"
  },
  {
    name: "Vandrevala Foundation Helpline",
    number: "+91 9999 666 555",
    category: "24/7 Crisis Counseling",
    actionUrl: "tel:+919999666555",
    description: "Free, confidential 24/7 clinical counseling support.",
    icon: "favorite"
  },
  {
    name: "MedAccess 24/7 Clinical Emergency Desk",
    number: "1800-MED-ACCESS",
    category: "Clinical Triage & Ambulance Dispatch",
    actionUrl: "tel:1800633222",
    description: "Immediate institutional medical escort, ER copay triage, and emergency dispatch.",
    icon: "medical_services"
  }
];

const SYSTEM_PROMPT = `You are the MedAccess 24/7 Clinical & Psychological First Aid Assistant. 
Your primary goals are:
1. Practice active listening, validate emotional distress and physical symptoms with deep clinical empathy.
2. Keep your answers concise, reassuring, and compassionate (2-4 sentences max). Never sound bureaucratic or dismissive.
3. Offer immediate grounding techniques (e.g., "Take a slow breath, I am here with you").
4. Reassure the patient that institutional emergency medical copay relief and clinical staff are actively processing their request.
5. If immediate physical danger, medical emergency, or self-harm is mentioned, gently urge them to connect with our live emergency numbers or visit the nearest ER immediately.`;

/**
 * Psychological First Aid (RAPID Protocol) Response Generator
 */
export function generateRogerianPFAResponse(
  studentMessage: string, 
  isCrisis: boolean,
  isHardshipWithConfirmation = false,
  isTicketCreated = false
): string {
  if (isCrisis) {
    return "I hear how deeply overwhelming and painful things are right now, but please know that you are not alone and your life has immense value. Take a slow breath with me—I am right here with you. Our campus emergency welfare team has been notified, and I strongly encourage you to connect with our 24/7 crisis numbers below right now for live, confidential support.";
  }

  if (isTicketCreated) {
    return "I hear you, and your emergency grant and welfare ticket has been officially submitted to our welfare desk. Our team is prioritizing your request right now. Take a calm breath—we are working on getting you relief as quickly as possible.";
  }

  if (isHardshipWithConfirmation) {
    const lower = studentMessage.toLowerCase();
    if (lower.includes('rent') || lower.includes('evict') || lower.includes('housing')) {
      return "I hear how deeply stressful and urgent this housing situation is. Take a slow, steady breath—you are not alone. Would you like me to submit an official Emergency Housing Grant ticket for university welfare review?";
    }
    if (lower.includes('food') || lower.includes('hungry') || lower.includes('meal')) {
      return "Facing food insecurity is very stressful, and it is completely understandable to feel overwhelmed. Would you like me to submit an Emergency Meal & Grocery Grant ticket for you right away?";
    }
    return "I hear how challenging this financial situation is right now. Please take a gentle breath. Would you like me to submit an official Emergency Welfare & Grant Assistance ticket to the student aid desk on your behalf?";
  }

  const lower = studentMessage.toLowerCase();
  if (lower.includes('hi') || lower.includes('hello') || lower.includes('hey')) {
    return "Hello! I am your University Crisis Counselor & Welfare Advisor. How are you doing today? Feel free to share what is on your mind.";
  }

  if (lower.includes('exam') || lower.includes('fail') || lower.includes('degree') || lower.includes('study') || lower.includes('class')) {
    return "Academic pressure can feel extraordinarily heavy, and it makes complete sense that you are feeling stressed. Please take a gentle breath—your worth and well-being come first. I am here to help you talk through this.";
  }

  if (lower.includes('lonely') || lower.includes('sad') || lower.includes('cry') || lower.includes('depress') || lower.includes('anxious') || lower.includes('panic')) {
    return "Thank you for reaching out and sharing this with me. I hear the weight you are carrying, and everything you are feeling right now is completely valid. Take a slow, grounding breath with me—I am here with you.";
  }

  return "I hear how much is on your mind right now, and I appreciate you sharing this with me. Take a slow, calm breath—I am right here with you, and university support services are always available.";
}

export interface CounselorResponseResult {
  reply: string;
  isCrisisResponse: boolean;
  requiresConfirmation: boolean;
  isTicketLogged: boolean;
  resources: EmergencyResourceCard[] | null;
  messageId?: string;
  latencyMs: number;
}

/**
 * Generates an empathetic Psychological First Aid counselor response using local ONNX model
 * or PFA Rogerian engine, intelligent ticket confirmation, and logs into Supabase.
 */
export async function generateCounselorResponse(
  ticketId: string | null,
  studentMessage: string,
  history: Array<{ sender: string; message: string }> = [],
  options: { 
    isTicketCreated?: boolean; 
    requiresConfirmation?: boolean;
    diagnosticContext?: DiagnosticSummaryContext;
  } = {}
): Promise<CounselorResponseResult> {
  const startTime = Date.now();

  // Route directly to diagnostic interpretation if context is present
  if (options.diagnosticContext) {
    return interpretDiagnosticResult(options.diagnosticContext, studentMessage, history);
  }

  // Step A: Safety & Harm Detection
  const isCrisisResponse = CRITICAL_SELF_HARM_REGEX.test(studentMessage);
  const isHardship = RELIEF_HARDSHIP_REGEX.test(studentMessage);
  const suggestedResources = isCrisisResponse ? EMERGENCY_RESOURCES : null;

  const isTicketLogged = !!ticketId;
  const requiresConfirmation = !isTicketLogged && !isCrisisResponse && isHardship;

  let counselorReply = '';

  try {
    const generator = await getCounselorPipeline();
    if (generator && !requiresConfirmation) {
      // Step B: Build Multi-Turn ChatML Prompt
      const messages = [
        { role: 'system', content: SYSTEM_PROMPT },
        ...history.slice(-4).map((msg) => ({
          role: msg.sender === 'STUDENT' ? 'user' : 'assistant',
          content: msg.message
        })),
        { role: 'user', content: studentMessage }
      ];

      // Limit generation tokens and race with a 2.5s safety timeout for real-time responsiveness
      const genPromise = generator(messages, {
        max_new_tokens: 45,
        temperature: 0.6,
        top_p: 0.85,
        do_sample: true
      });

      const timeoutPromise = new Promise((_, reject) =>
        setTimeout(() => reject(new Error('Inference timeout')), 2500)
      );

      const output: any = await Promise.race([genPromise, timeoutPromise]);

      if (Array.isArray(output) && output.length > 0) {
        const genText = output[0]?.generated_text;
        if (Array.isArray(genText)) {
          const lastMsg = genText.at(-1);
          counselorReply = lastMsg?.content?.trim() || '';
        } else if (typeof genText === 'string') {
          counselorReply = genText.replace(/<\|.*?\|>/g, '').trim();
          if (counselorReply.includes('assistant\n')) {
            counselorReply = counselorReply.split('assistant\n').pop()?.trim() || counselorReply;
          }
        }
      }
    }
  } catch (modelErr) {
    // Falls back seamlessly to Rogerian PFA generator
  }

  // Filter out any AI disclaimers, repetition, or prompt regurgitation
  const lowerReply = counselorReply.toLowerCase();
  const isInvalidText =
    !counselorReply ||
    counselorReply.length < 20 ||
    lowerReply.includes('ai language model') ||
    lowerReply.includes('practice active listening') ||
    lowerReply.includes('validate their pain') ||
    lowerReply.includes('keep your answer') ||
    lowerReply.includes('here is what i suggest') ||
    lowerReply.includes('get rid of') ||
    lowerReply.includes('crap');

  if (isInvalidText || requiresConfirmation || options.isTicketCreated) {
    counselorReply = generateRogerianPFAResponse(
      studentMessage, 
      isCrisisResponse, 
      requiresConfirmation, 
      options.isTicketCreated
    );
  }

  // Ensure life-safety hotline advisory is attached if crisis triggered
  if (isCrisisResponse && !counselorReply.includes('14416') && !counselorReply.includes('hotline') && !counselorReply.includes('crisis')) {
    counselorReply += "\n\nPlease reach out to our 24/7 crisis numbers below right now—counselors are ready to speak with you.";
  }

  const latencyMs = Date.now() - startTime;
  const outputTokens = counselorReply.split(/\s+/).length;

  // Telemetry logs
  console.log(`💬 [Crisis Counselor] Generated active support response | Ticket: ${ticketId || 'None (General/Pre-Confirmation)'} | Crisis Protocol: ${isCrisisResponse} | Ticket Logged: ${isTicketLogged}`);
  console.log(`🧠 [Local Counselor AI] Generated empathetic response in ${latencyMs}ms | Tokens: ${outputTokens}`);

  // Step D: Store in Supabase ticket_messages if ticket exists
  let messageId: string | undefined;
  if (ticketId) {
    try {
      const { data: inserted, error: insertError } = await supabase
        .from('ticket_messages')
        .insert([
          {
            ticket_id: ticketId,
            sender: 'COUNSELOR_AI',
            message: counselorReply,
            is_crisis_response: isCrisisResponse,
            suggested_resources: suggestedResources
          }
        ])
        .select('id')
        .single();

      if (insertError) {
        console.warn(`[CrisisCounselorService] Supabase ticket_messages insert notice: ${insertError.message}`);
      } else if (inserted) {
        messageId = inserted.id;
      }
    } catch (dbErr) {
      console.warn(`[CrisisCounselorService] Database insert notice:`, dbErr);
    }
  }

  return {
    reply: counselorReply,
    isCrisisResponse,
    requiresConfirmation,
    isTicketLogged,
    resources: suggestedResources,
    messageId,
    latencyMs
  };
}
