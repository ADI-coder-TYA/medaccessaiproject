import { GoogleGenerativeAI } from '@google/generative-ai';
import { supabase } from '../config/supabase.js';
import { getIO } from './socketManager.js';
import { PatientClinicalRagService } from './patientClinicalRagService.js';


const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY || '');
// gemini-flash-lite-latest: lowest token footprint and highest rate limit ceiling
const flashLiteModel = genAI.getGenerativeModel({
  model: 'gemini-flash-lite-latest',
  generationConfig: {
    maxOutputTokens: 50,
    temperature: 0.5,
  },
});

// In-memory cache to prevent redundant API calls (0 tokens used for repeated phrases)
const responseCache = new Map<string, { reply: string; timestamp: number }>();
const CACHE_TTL_MS = 10 * 60 * 1000; // 10 minutes

// Per-claim rate-limit throttle timestamp
const claimLastCall = new Map<string, number>();

export const LIFE_SAFETY_REGEX = /\b(suicid(e|al)|kill myself|end my life|self harm|hurt myself|want to die|overdose|severe bleeding|chest pain|unconscious|cant breathe|cannot breathe|heart attack|stroke)\b/i;

export interface EmergencyHelpline {
  name: string;
  number: string;
  category: string;
  actionUrl: string;
  description: string;
  icon: string;
}

export const CLINICAL_EMERGENCY_RESOURCES: EmergencyHelpline[] = [
  {
    name: "Tele-MANAS (Govt of India)",
    number: "14416",
    category: "Mental Health & Crisis Hotline",
    actionUrl: "tel:14416",
    description: "Toll-free 24/7 National Tele-Mental Health Programme (or 1800-891-4416).",
    icon: "support_agent",
  },
  {
    name: "Vandrevala Mental Health Helpline",
    number: "+91 9999 666 555",
    category: "24/7 Psychological First Aid",
    actionUrl: "tel:+919999666555",
    description: "Free, confidential 24/7 clinical counseling & de-escalation.",
    icon: "favorite",
  },
  {
    name: "988 Suicide & Crisis Lifeline (US)",
    number: "988",
    category: "Immediate Emergency Lifeline",
    actionUrl: "tel:988",
    description: "24/7 confidential clinical support for acute distress or self-harm prevention.",
    icon: "crisis_alert",
  },
  {
    name: "Campus 24/7 Medical Emergency Desk",
    number: "1800-MED-ACCESS",
    category: "Clinical Triage & Ambulance Dispatch",
    actionUrl: "tel:1800633222",
    description: "Institutional emergency medical escort, ER copay triage, and ambulance dispatch.",
    icon: "medical_services",
  },
];

const COMPACT_SYSTEM_PROMPT = `You are the MedAccess AI Clinical Assistant. Give a warm, empathetic 1-2 sentence reassurance to the patient. Tell them their copay and medical triage is actively underway.`;

export interface ClinicalCounselorResponse {
  reply: string;
  isCrisisResponse: boolean;
  isLifeSafetyAlert: boolean;
  resources: EmergencyHelpline[] | null;
  latencyMs: number;
}

/**
 * Psychological First Aid Rogerian local fallback generator (0 API calls, 0 tokens)
 */
function getRogerianPFABackup(patientMessage: string, isLifeSafety: boolean): string {
  if (isLifeSafety) {
    return "I hear how deeply overwhelming and acute things are right now. Please take a slow, steady breath with me—you are not alone and your safety is our utmost priority. Our emergency medical triage desk has been alerted, and I strongly urge you to call one of the 24/7 crisis numbers below right now for immediate support.";
  }

  const lower = patientMessage.toLowerCase();
  if (lower.includes('pain') || lower.includes('er') || lower.includes('hospital') || lower.includes('doctor') || lower.includes('accident') || lower.includes('prescription') || lower.includes('medicine') || lower.includes('scan')) {
    return "I hear what you are experiencing with your medical needs right now. Take a calm, gentle breath. Your emergency medical copay request is actively being triaged by our clinical team to ensure you receive immediate assistance.";
  }

  if (lower.includes('anxious') || lower.includes('panic') || lower.includes('scared') || lower.includes('stress') || lower.includes('overwhelm') || lower.includes('sad') || lower.includes('depress')) {
    return "Thank you for reaching out and sharing what you are going through. Everything you are feeling right now is completely valid. Take a slow, grounding breath with me—we are right here with you, and support is available 24/7.";
  }

  if (lower.includes('status') || lower.includes('update') || lower.includes('claim') || lower.includes('money') || lower.includes('copay')) {
    return "Your emergency claim is on record and our autonomous clinical engine is verifying your invoice and allocating available institutional copay relief. You can track live updates on your status board.";
  }

  return "I hear you, and thank you for connecting with MedAccess AI. Please take a gentle breath—our clinical team is reviewing your intake details and processing your assistance request without delay.";
}

/**
 * Generates an empathetic clinical PFA response using gemini-flash-lite-latest with
 * token throttling, caching, and local Rogerian fallback on rate limit (429).
 */
export async function generateClinicalCounselorResponse(
  claimId: string,
  patientMessage: string,
  history: Array<{ sender: string; message: string }> = []
): Promise<ClinicalCounselorResponse> {
  const startTime = Date.now();

  // Step A: Life-Safety Pattern Check
  const isLifeSafetyAlert = LIFE_SAFETY_REGEX.test(patientMessage);
  const isCrisisResponse = isLifeSafetyAlert;
  const suggestedResources = isLifeSafetyAlert ? CLINICAL_EMERGENCY_RESOURCES : null;

  const cacheKey = patientMessage.trim().toLowerCase();
  const cached = responseCache.get(cacheKey);
  if (cached && Date.now() - cached.timestamp < CACHE_TTL_MS) {
    console.log(`⚡ [MedAccess Counselor] Served from memory cache (0 tokens used)`);
    return {
      reply: cached.reply,
      isCrisisResponse,
      isLifeSafetyAlert,
      resources: suggestedResources,
      latencyMs: Date.now() - startTime,
    };
  }

  let counselorReply = '';

  // Step B: Multi-entity Clinical Claims RAG Retrieval & Flash Lite API call
  if (process.env.GEMINI_API_KEY) {
    const lastCall = claimLastCall.get(claimId) || 0;
    const now = Date.now();
    
    // Throttle calls from same session to at most 1 every 1500ms
    if (now - lastCall < 1500) {
      console.log(`🛡️ [MedAccess Counselor] Throttling rapid request -> using local Rogerian engine to save API quota`);
      counselorReply = getRogerianPFABackup(patientMessage, isLifeSafetyAlert);
    } else {
      claimLastCall.set(claimId, now);
      try {
        let ragContextBlock = '';
        try {
          const ragContext = await PatientClinicalRagService.retrieveClaimContext(claimId);
          ragContextBlock = PatientClinicalRagService.formatRagContextForPrompt(ragContext, 'CLAIM_TRIAGE');
        } catch (ragErr) {
          console.warn(`[MedAccess Counselor] Claim RAG notice:`, ragErr);
        }

        const prompt = `${COMPACT_SYSTEM_PROMPT}\n${ragContextBlock}\nPatient: "${patientMessage.slice(0, 300)}"\nResponse:`;
        const genPromise = flashLiteModel.generateContent(prompt);
        const timeoutPromise = new Promise((_, reject) =>
          setTimeout(() => reject(new Error('AI generation timeout')), 2200)
        );

        const res: any = await Promise.race([genPromise, timeoutPromise]);
        const text = res?.response?.text?.() || '';
        if (text) {
          counselorReply = text.trim();
          // Cache successful response to save tokens on future calls
          responseCache.set(cacheKey, { reply: counselorReply, timestamp: Date.now() });
        }
      } catch (apiErr: any) {
        console.warn(`⚠️ [MedAccess Counselor] Flash-Lite API error/limit: ${apiErr?.message || apiErr}. Seamlessly falling back to local Rogerian PFA.`);
        counselorReply = getRogerianPFABackup(patientMessage, isLifeSafetyAlert);
      }
    }
  }


  // Validate reply text
  const lower = counselorReply.toLowerCase();
  const isInvalid =
    !counselorReply ||
    counselorReply.length < 15 ||
    lower.includes('ai language model') ||
    lower.includes('system prompt') ||
    lower.includes('objectives:');

  if (isInvalid) {
    counselorReply = getRogerianPFABackup(patientMessage, isLifeSafetyAlert);
  }

  // Step C: Life-Safety Database Escalation & War Room Notification
  if (isLifeSafetyAlert && claimId) {
    try {
      await supabase
        .from('claims')
        .update({
          esi_level: 'ESI_1_CRITICAL',
          is_life_safety_alert: true,
          status: 'Triage Active',
          updated_at: new Date().toISOString(),
        })
        .eq('id', claimId);

      // Emit emergency alert to Admin War Room
      try {
        const io = getIO();
        io.emit('emergency:alert', {
          claimId,
          esiLevel: 'ESI_1_CRITICAL',
          isLifeSafetyAlert: true,
          patientMessage,
          timestamp: new Date().toISOString(),
        });
        io.to(`claim:${claimId}`).emit('emergency:alert', {
          claimId,
          esiLevel: 'ESI_1_CRITICAL',
          isLifeSafetyAlert: true,
          resources: suggestedResources,
        });
      } catch (_) {}
    } catch (dbErr) {
      console.warn(`[ClinicalCounselor] Escalation write warning:`, dbErr);
    }
  }

  const latencyMs = Date.now() - startTime;
  console.log(`💬 [MedAccess Counselor] Generated response for Claim ${claimId} in ${latencyMs}ms | Crisis: ${isCrisisResponse}`);

  return {
    reply: counselorReply,
    isCrisisResponse,
    isLifeSafetyAlert,
    resources: suggestedResources,
    latencyMs,
  };
}
