import {
  CDSSInputPayload,
  DifferentialDiagnosisCandidate,
  TreatmentPathway,
  WHO_ICD11_URI_STEM
} from './types.js';
import { ICD11ConceptStore } from './ICD11ConceptStore.js';
import { TreatmentPathwayAdvisor } from './TreatmentPathwayAdvisor.js';

export interface QwenCDSSPredictionResult {
  primaryDiagnosis: {
    code: string;
    title: string;
    category?: string;
    uri?: string;
    urgencyLevel: 'ROUTINE' | 'PROMPT_EVALUATION' | 'IMMEDIATE_EMERGENCY';
    clinicalSummary: string;
  };
  differentialDiagnoses: DifferentialDiagnosisCandidate[];
  treatmentPathway: TreatmentPathway;
  model: string;
  latencyMs: number;
}

export class QwenInferenceService {
  private static readonly MODEL_ID = 'Qwen/Qwen2.5-72B-Instruct';
  private static readonly HF_ROUTER_URL = 'https://router.huggingface.co/v1/chat/completions';
  private static readonly HF_API_URL = 'https://api-inference.huggingface.co/models/Qwen/Qwen2.5-72B-Instruct/v1/chat/completions';

  // Purely respiratory ICD-11 categories that must receive strict 0% probability when non-respiratory
  private static readonly PURELY_RESPIRATORY_CODES = new Set(['1B10.0', '1B10', 'CA00', 'CA01', 'CA0B', 'CA40']);

  /**
   * Check if Hugging Face token is configured for Cloud Inference
   */
  public static isConfigured(): boolean {
    return Boolean(process.env.HF_TOKEN && process.env.HF_TOKEN.trim().length > 0);
  }

  /**
   * Run Cloud Inference using Qwen/Qwen2.5-72B-Instruct on Hugging Face
   */
  public static async predictDisease(
    payload: CDSSInputPayload,
    temperature = 1.25
  ): Promise<QwenCDSSPredictionResult> {
    const token = process.env.HF_TOKEN;
    if (!token || token.trim().length === 0) {
      console.error('❌ [QwenCDSS] Blockage: HF_TOKEN is missing or empty in environment. Cannot contact Hugging Face Cloud.');
      throw new Error('HF_TOKEN is not configured in environment');
    }

    const maskedToken = `${token.trim().substring(0, 4)}...${token.trim().slice(-4)}`;
    const startTime = Date.now();
    const systemPrompt = this.buildSystemPrompt();
    const userPrompt = this.buildUserPrompt(payload);

    const symptomCount = Array.isArray(payload.symptoms?.symptoms) ? payload.symptoms.symptoms.length : 0;
    const bodyLoc = (payload as any).anatomicalLocation || (payload.symptoms as any)?.anatomicalLocation || payload.symptoms?.bodyLocation || 'unspecified';
    const visionCount = payload.visionFindings?.length || 0;
    const hasAudio = Boolean(payload.audioClassification);

    console.log(`🤖 [QwenCDSS] Initiating cloud disease prediction:
  - Patient: ${payload.patientId || 'anonymous'}
  - Body Location: ${bodyLoc}
  - Symptoms: ${symptomCount} items
  - Vision Findings: ${visionCount} items
  - Audio Classification: ${hasAudio ? `${payload.audioClassification?.predictedCategory} (${((payload.audioClassification?.confidence || 0) * 100).toFixed(1)}%)` : 'none'}
  - Risk Score: ${payload.multimodalRiskScore}
  - Auth: Token configured (${maskedToken})`);

    let rawResponseText = '';
    const requestBody = {
      model: this.MODEL_ID,
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userPrompt }
      ],
      temperature: 0.2, // Low temperature for high clinical precision
      max_tokens: 2048, // Generous token budget for complete 72B clinical JSON
      response_format: { type: 'json_object' }
    };

    const headers = {
      'Authorization': `Bearer ${token.trim()}`,
      'Content-Type': 'application/json'
    };

    let response: Response | null = null;
    let lastError: any = null;

    // Retry up to 2 times on router with 90s timeout
    for (let attempt = 1; attempt <= 2; attempt++) {
      const attemptStart = Date.now();
      try {
        console.log(`🚀 [QwenCDSS] Calling Hugging Face Router [Attempt ${attempt}/2] -> ${this.HF_ROUTER_URL}`);
        const controller = new AbortController();
        const timeout = setTimeout(() => {
          console.warn(`⏱️ [QwenCDSS] Blockage: Request exceeded 90s timeout limit on attempt ${attempt}. Aborting connection...`);
          controller.abort();
        }, 90000);

        response = await fetch(this.HF_ROUTER_URL, {
          method: 'POST',
          headers,
          body: JSON.stringify(requestBody),
          signal: controller.signal
        });
        clearTimeout(timeout);

        const attemptDuration = Date.now() - attemptStart;

        if (response.ok) {
          console.log(`✅ [QwenCDSS] Hugging Face Router responded [HTTP ${response.status}] in ${attemptDuration}ms`);
          break;
        }

        const errText = await response.text();
        console.warn(`⚠️ [QwenCDSS] Attempt ${attempt} failed with HTTP ${response.status} (${response.statusText}) in ${attemptDuration}ms. Response body: ${errText.slice(0, 300)}`);
        
        if (response.status === 401 || response.status === 403) {
          console.error(`🔒 [QwenCDSS] Blockage: Hugging Face authentication failed (HTTP ${response.status}). Check HF_TOKEN validity and read permissions.`);
          throw new Error(`HF Authentication Error [${response.status}]: ${errText}`);
        } else if (response.status === 429) {
          console.warn(`⏳ [QwenCDSS] Blockage: Hugging Face router rate-limited (HTTP 429). Exponential backoff 2000ms before retry...`);
          await new Promise((r) => setTimeout(r, 2000));
        } else if (response.status === 503) {
          console.warn(`⏳ [QwenCDSS] Blockage: Upstream model cold start / loading (HTTP 503). Waiting 3000ms for warm-up...`);
          await new Promise((r) => setTimeout(r, 3000));
        } else if (response.status >= 500) {
          console.warn(`⚠️ [QwenCDSS] Upstream HF server error (${response.status}). Backing off 2000ms...`);
          await new Promise((r) => setTimeout(r, 2000));
        } else {
          throw new Error(`HF Router error [${response.status}]: ${errText}`);
        }
      } catch (err: any) {
        lastError = err;
        const attemptDuration = Date.now() - attemptStart;
        console.error(`❌ [QwenCDSS] Attempt ${attempt} network error after ${attemptDuration}ms: ${err.message}`);
        if (attempt < 2) {
          console.log(`🔄 [QwenCDSS] Scheduling retry attempt 2...`);
          await new Promise((r) => setTimeout(r, 2000));
        }
      }
    }

    if (!response || !response.ok) {
      console.error(`🚨 [QwenCDSS] Critical Blockage: All cloud inference attempts exhausted. Last Error: ${lastError?.message || 'Unknown'}`);
      throw lastError || new Error('Hugging Face cloud inference failed after attempts');
    }

    const data = await response.json();
    rawResponseText = data.choices?.[0]?.message?.content || '';

    console.log(`📄 [QwenCDSS] Received raw payload (${rawResponseText.length} chars). Parsing & applying clinical guardrails...`);
    const parsedJson = this.cleanAndParseJSON(rawResponseText);
    const latencyMs = Date.now() - startTime;

    const result = this.postProcessPredictions(parsedJson, payload, temperature, latencyMs);
    console.log(`🎉 [QwenCDSS] Disease prediction complete: Primary="${result.primaryDiagnosis.code} - ${result.primaryDiagnosis.title}", Differentials=${result.differentialDiagnoses.length} candidates (${latencyMs}ms total)`);
    return result;
  }

  /**
   * System Prompt instructing Qwen2.5-72B-Instruct on ICD-11 coding & clinical safety
   */
  private static buildSystemPrompt(): string {
    const knownConcepts = ICD11ConceptStore.getAllConcepts();
    const conceptCatalog = knownConcepts
      .map((c) => `- Code: ${c.code} | Title: ${c.title} | Category: ${c.category}`)
      .join('\n');

    return `You are an elite Clinical Decision Support System (CDSS) AI specialized in differential disease diagnosis and WHO ICD-11 coding.

Available Core ICD-11 Catalog:
${conceptCatalog}

Analyze patient presenting signs, symptoms, anatomical location, vital signs, cough acoustic classification, vision findings, and multimodal risk score.
When a Bioacoustic Biomarker Profile (extracted via Meyda DSP) is present:
- Synthesize the acoustic sound phenotype, spectral frequency centroid (pitch/brightness), rolloff, onset flux, airway turbulence (ZCR), and cepstral timbre (MFCC) into your differential diagnostic reasoning.
- High spectral centroid (>1500 Hz) + high turbulence/ZCR strongly points to airway obstruction, bronchospasm, or wheeze (e.g. Asthma, Bronchospasm).
- Mid-frequency centroid (700-1400 Hz) + productive cough + rapid explosive flux strongly points to lower respiratory tract secretions (e.g. Pneumonia CA40, Acute Bronchitis CA00).
- Normal or absent acoustic sounds with ocular/skin presentations should confirm non-respiratory primary pathology.

Diagnose the most accurate primary disease condition and generate 3 to 6 differential diagnosis candidates ranked by probability.

Output STRICT JSON conforming to this schema without any markdown formatting or commentary:
{
  "differentialDiagnoses": [
    {
      "code": string, // Official ICD-11 Code (e.g. 1B10.0, CA40, 9A60, FB80, BA00, etc.)
      "title": string, // Official ICD-11 Disease Title
      "category": string, // Medical Category (e.g. Respiratory Diseases, Ophthalmology, Dermatology)
      "probability": number, // Normalized probability between 0.01 and 0.99
      "logitScore": number, // Estimated logit score between -10.0 and 10.0
      "matchedCriteria": string[], // Symptoms, locations, vitals that triggered this diagnosis
      "clinicalRationale": string // Detailed clinical rationale explaining why this diagnosis fits
    }
  ],
  "primaryDiagnosis": {
    "code": string,
    "title": string,
    "category": string,
    "urgencyLevel": "ROUTINE" | "PROMPT_EVALUATION" | "IMMEDIATE_EMERGENCY",
    "clinicalSummary": string
  },
  "recommendedTreatment": {
    "firstLineMedications": [
      {
        "genericName": string,
        "dosage": string,
        "frequency": string,
        "duration": string,
        "clinicalNotes": string
      }
    ],
    "labOrders": string[],
    "imagingOrders": string[],
    "monitoringFrequency": string,
    "followUpDays": number,
    "urgentRedFlags": string[]
  }
}`;
  }

  /**
   * Construct structured prompt from patient assessment payload
   */
  private static buildUserPrompt(payload: CDSSInputPayload): string {
    const symptomsList: string[] = [
      ...(Array.isArray(payload.symptoms?.symptoms) ? payload.symptoms.symptoms : []),
      ...(Array.isArray((payload.symptoms as any)?.symptomList) ? (payload.symptoms as any).symptomList : [])
    ];
    const anatomical = (payload as any).anatomicalLocation || (payload.symptoms as any)?.anatomicalLocation || payload.symptoms?.bodyLocation || 'Unspecified';
    const vitals = payload.symptoms?.vitals || {};
    const vision = payload.visionFindings || [];
    const rawAudio = payload.audioClassification as any;
    const audio = rawAudio?.classification || rawAudio;
    const audioCategory = audio?.predictedCategory;
    const audioConfidence = audio?.confidence ? Math.round(Number(audio.confidence) * 100) : null;
    const audioStr = audioCategory ? `${audioCategory} (${audioConfidence ?? 0}%)` : 'None';

    const semanticProfile = payload.acousticProfile || audio?.semanticAcousticProfile;
    let acousticFormattedSection = `- Acoustic Audio Classification: ${audioStr}`;
    if (semanticProfile) {
      acousticFormattedSection = `- Bioacoustic Biomarker Profile (Meyda DSP Audio Feature Extraction):\n  * ${semanticProfile.split('\n').join('\n  * ')}`;
    } else if (audioCategory) {
      acousticFormattedSection = `- Bioacoustic Biomarker Profile (Meyda DSP Audio Feature Extraction):\n  * Auscultation Sound: ${audioCategory} (${audioConfidence ?? 0}% confidence)\n  * Acoustic Phenotype: ${audioCategory.includes('Wheeze') ? 'High-frequency wheezing / bronchospasm harmonics' : audioCategory.includes('Wet') ? 'Productive lower respiratory secretions' : audioCategory.includes('Dry') ? 'Irritative non-productive cough' : 'Normal laminar breath sound'}`;
    }

    return `PATIENT PRESENTATION:
- Presenting Symptoms: ${symptomsList.join(', ') || 'General malaise'}
- Anatomical Location: ${anatomical}
- Pain Scale: ${payload.symptoms?.painScale ?? 'N/A'}/10
- Duration: ${payload.symptoms?.durationDays ?? 'N/A'} days
- Vital Signs:
  * Temperature: ${vitals.temperatureCelsius ?? 'N/A'} °C
  * Heart Rate: ${vitals.heartRate ?? 'N/A'} bpm
  * Blood Pressure: ${vitals.systolicBP ?? 'N/A'}/${vitals.diastolicBP ?? 'N/A'} mmHg
  * SpO2: ${vitals.oxygenSaturation ?? 'N/A'} %
  * Respiratory Rate: ${vitals.respirationRate ?? 'N/A'} breaths/min
- Vision Findings: ${vision.length > 0 ? vision.map((v) => `${v.condition} (${Math.round(v.confidence * 100)}%)`).join(', ') : 'None'}
${acousticFormattedSection}
- Multimodal Risk Score: ${payload.multimodalRiskScore}

Generate differential diagnoses and evidence-based treatment pathway.`;
  }

  /**
   * Clean markdown wrapper tags and parse JSON safely
   */
  private static cleanAndParseJSON(text: string): any {
    let cleaned = text.trim();
    if (cleaned.startsWith('```json')) {
      cleaned = cleaned.substring(7);
    } else if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(3);
    }
    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }
    cleaned = cleaned.trim();

    try {
      return JSON.parse(cleaned);
    } catch (e: any) {
      console.warn(`⚠️ [QwenCDSS] Standard JSON.parse failed (${e.message}). Attempting regex & structural auto-repair...`);
      // First attempt: match from first '{' to last '}'
      const firstBrace = cleaned.indexOf('{');
      const lastBrace = cleaned.lastIndexOf('}');
      if (firstBrace !== -1 && lastBrace !== -1 && lastBrace > firstBrace) {
        try {
          const parsed = JSON.parse(cleaned.substring(firstBrace, lastBrace + 1));
          console.log(`🛠️ [QwenCDSS] Successfully recovered valid JSON using brace boundary slice.`);
          return parsed;
        } catch (_) {}
      }

      // Second attempt: auto-close open brackets/braces if truncated
      try {
        let repaired = cleaned.substring(firstBrace !== -1 ? firstBrace : 0);
        // Remove trailing commas or incomplete string quotes
        repaired = repaired.replace(/,\s*$/, '');
        const quoteCount = (repaired.match(/"/g) || []).length;
        if (quoteCount % 2 !== 0) repaired += '"';
        const openBraces = (repaired.match(/\{/g) || []).length;
        const closeBraces = (repaired.match(/\}/g) || []).length;
        const openBrackets = (repaired.match(/\[/g) || []).length;
        const closeBrackets = (repaired.match(/\]/g) || []).length;

        for (let i = 0; i < openBrackets - closeBrackets; i++) repaired += ']';
        for (let i = 0; i < openBraces - closeBraces; i++) repaired += '}';
        const parsed = JSON.parse(repaired);
        console.log(`🛠️ [QwenCDSS] Successfully auto-repaired truncated JSON by balancing ${openBrackets - closeBrackets} brackets and ${openBraces - closeBraces} braces.`);
        return parsed;
      } catch (_) {}

      console.error(`❌ [QwenCDSS] Blockage: Completely unparseable JSON payload from Qwen. Snippet: "${text.slice(0, 300)}"`);
      throw new Error(`Failed to parse Qwen JSON response: ${e.message}`);
    }
  }

  /**
   * Applies guardrails (Anatomical Gating, ICD-11 Concept validation, Softmax Temperature Scaling)
   */
  private static postProcessPredictions(
    rawJson: any,
    payload: CDSSInputPayload,
    temperature = 1.25,
    latencyMs: number
  ): QwenCDSSPredictionResult {
    const rawAnatomical = ((payload as any).anatomicalLocation || (payload.symptoms as any)?.anatomicalLocation || payload.symptoms?.bodyLocation || '').toLowerCase();
    const isOcular = rawAnatomical.includes('eye') || rawAnatomical.includes('ophthalm');
    const isSkin = !isOcular && (rawAnatomical.includes('skin') || rawAnatomical.includes('epidermis'));

    const rawDiffs: any[] = Array.isArray(rawJson.differentialDiagnoses) ? rawJson.differentialDiagnoses : [];

    // Map each candidate and check concept store
    const candidates: DifferentialDiagnosisCandidate[] = [];

    for (const d of rawDiffs) {
      let code = String(d.code || '').trim().toUpperCase();
      let concept = ICD11ConceptStore.getConceptByCode(code);

      // Try finding by title if code wasn't matched directly
      if (!concept && d.title) {
        const found = ICD11ConceptStore.findConceptByKeyword(d.title);
        if (found) {
          concept = found;
          code = found.code;
        }
      }

      const title = concept?.title || d.title || code;
      const category = concept?.category || d.category || 'General Medicine';
      const uri = concept?.uri || `${WHO_ICD11_URI_STEM}/${code}`;

      let isMasked = false;
      // Guardrail 1 & 2: Anatomical Hard-Gating
      if (isOcular && (this.PURELY_RESPIRATORY_CODES.has(code) || category === 'Respiratory Diseases')) {
        isMasked = true;
        console.log(`🛡️ [QwenCDSS] Anatomical hard-gating masked out discordant respiratory code "${code} ${title}" for ocular presentation.`);
      } else if (isSkin && (this.PURELY_RESPIRATORY_CODES.has(code) || category === 'Respiratory Diseases')) {
        isMasked = true;
        console.log(`🛡️ [QwenCDSS] Anatomical hard-gating masked out discordant respiratory code "${code} ${title}" for skin presentation.`);
      }

      let logit = Number(d.logitScore);
      if (isNaN(logit)) {
        logit = Math.log(Math.max(0.01, Number(d.probability) || 0.2));
      }
      if (isMasked) {
        logit = -99.0;
      } else {
        // Clip logit to [-20, 20]
        logit = Math.max(-20.0, Math.min(20.0, logit));
      }

      candidates.push({
        code,
        title,
        category,
        uri,
        probability: isMasked ? 0.0 : Math.max(0.01, Number(d.probability) || 0.1),
        logitScore: logit,
        matchedCriteria: isMasked
          ? ['Anatomical hard-gating exclusion: discordant presenting body region']
          : Array.isArray(d.matchedCriteria)
            ? d.matchedCriteria
            : ['Clinical correlation'],
        clinicalRationale: isMasked
          ? 'Anatomically filtered out'
          : d.clinicalRationale || 'Derived via Qwen 2.5 72B clinical reasoning'
      });
    }

    // Apply Softmax Temperature Scaling on unmasked logits
    const safeTemp = Math.max(0.5, Math.min(3.0, temperature || 1.25));
    const validLogits = candidates
      .filter((c) => c.logitScore > -90)
      .map((c) => c.logitScore / safeTemp);

    const maxLogit = validLogits.length > 0 ? Math.max(...validLogits) : 0;
    const expScores = candidates.map((c) => (c.logitScore <= -90 ? 0 : Math.exp((c.logitScore / safeTemp) - maxLogit)));
    const sumExp = expScores.reduce((a, b) => a + b, 0);

    candidates.forEach((c, i) => {
      if (c.logitScore <= -90 || sumExp === 0) {
        c.probability = 0.0;
      } else {
        c.probability = Math.round((expScores[i] / sumExp) * 10000) / 10000;
      }
    });

    // Sort descending by probability
    candidates.sort((a, b) => b.probability - a.probability);

    // Primary diagnosis resolution
    const topCandidate = candidates[0] || {
      code: 'MG40',
      title: 'General Examination or Investigation',
      category: 'General',
      uri: `${WHO_ICD11_URI_STEM}/MG40`,
      probability: 1.0,
      logitScore: 0.0,
      matchedCriteria: ['Default presentation'],
      clinicalRationale: 'General clinical evaluation'
    };

    const rawPrimary = rawJson.primaryDiagnosis || {};
    const primaryCode = topCandidate.probability > 0 ? topCandidate.code : (rawPrimary.code || topCandidate.code);
    const primaryConcept = ICD11ConceptStore.getConceptByCode(primaryCode);

    // Formulate Treatment Pathway with TreatmentPathwayAdvisor or model outputs
    let treatmentPathway: TreatmentPathway;
    if (primaryConcept) {
      treatmentPathway = TreatmentPathwayAdvisor.recommendPathway(topCandidate, payload.multimodalRiskScore);
    } else {
      const rx = rawJson.recommendedTreatment?.firstLineMedications || [];
      treatmentPathway = {
        primaryCode,
        primaryTitle: topCandidate.title,
        recommendedRx: rx.map((m: any) => ({
          genericName: m.genericName || 'Prescription medication',
          dosage: m.dosage || 'Standard clinical dose',
          frequency: m.frequency || 'Daily',
          duration: m.duration || '5-7 days',
          clinicalNotes: m.clinicalNotes || 'As directed by physician'
        })),
        labOrders: rawJson.recommendedTreatment?.labOrders || ['Complete Blood Count (CBC)'],
        imagingOrders: rawJson.recommendedTreatment?.imagingOrders || [],
        monitoringFrequency: rawJson.recommendedTreatment?.monitoringFrequency || 'Routine monitoring',
        followUpDays: rawJson.recommendedTreatment?.followUpDays || 7,
        urgentRedFlags: rawJson.recommendedTreatment?.urgentRedFlags || ['Severe shortness of breath', 'High fever (>39°C)'],
        urgencyLevel: rawPrimary.urgencyLevel || 'PROMPT_EVALUATION'
      };
    }

    return {
      primaryDiagnosis: {
        code: primaryCode,
        title: topCandidate.title,
        category: topCandidate.category,
        uri: topCandidate.uri,
        urgencyLevel: treatmentPathway.urgencyLevel,
        clinicalSummary: rawPrimary.clinicalSummary || topCandidate.clinicalRationale
      },
      differentialDiagnoses: candidates,
      treatmentPathway,
      model: this.MODEL_ID,
      latencyMs
    };
  }
}
