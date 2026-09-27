import sharp from 'sharp';
import {
  ClinicalImageCategory,
  CloudVisionClassificationResult
} from './types.js';
import { VisionDiagnosticService } from './VisionDiagnosticService.js';
import { CLINICAL_VISION_CLASSES, ClinicalVisionClass } from './clinicalMobileNet.js';

export class CloudVisionClassifier {
  private static readonly HF_ROUTER_URL = 'https://router.huggingface.co/v1/chat/completions';
  private static readonly CLOUD_MODEL_ID = 'Qwen/Qwen2.5-VL-72B-Instruct';

  /**
   * Checks if Hugging Face Cloud Inference is configured with a valid token.
   */
  public static isCloudConfigured(): boolean {
    return Boolean(process.env.HF_TOKEN && process.env.HF_TOKEN.trim().length > 0);
  }

  /**
   * Performs advanced multimodal clinical image classification using Qwen 2.5-VL 72B Instruct.
   * Diagnoses dermatological rashes, skin lesions, ocular conditions (conjunctivitis/hemorrhage),
   * acute wounds/cuts/burns, and oral/throat infections.
   *
   * Automatically falls back to local Clinical MobileNet-V3 if offline or router errors out.
   */
  public static async classifyClinicalImage(
    rawBuffer: Buffer,
    categoryHint?: ClinicalImageCategory
  ): Promise<CloudVisionClassificationResult> {
    const startTime = Date.now();
    console.log(`👁️ [CloudVisionClassifier] Clinical image diagnostic analysis requested (${rawBuffer.length} bytes, categoryHint: ${categoryHint || 'auto'})...`);

    // 1. Try Hugging Face SOTA Multimodal Vision Model (Qwen/Qwen2.5-VL-72B-Instruct)
    if (this.isCloudConfigured()) {
      try {
        console.log(`🚀 [CloudVisionClassifier] Dispatching clinical photograph to [${this.CLOUD_MODEL_ID}]...`);
        const cloudResult = await this.callCloudVisionModel(rawBuffer, categoryHint);
        cloudResult.latencyMs = Date.now() - startTime;
        console.log(`✅ [CloudVisionClassifier] SOTA VLM inference succeeded: "${cloudResult.condition}" (${(cloudResult.confidence * 100).toFixed(1)}%) [Severity: ${cloudResult.severity}] in ${cloudResult.latencyMs}ms`);
        return cloudResult;
      } catch (err: any) {
        console.warn(`⚠️ [CloudVisionClassifier] Cloud VLM call failed (${err.message}). Engaging local MobileNet-V3 fallback...`);
      }
    } else {
      console.log(`ℹ️ [CloudVisionClassifier] HF_TOKEN not configured -> routing to local MobileNet-V3.`);
    }

    // 2. Offline / Error Fallback: Local TensorFlow.js Clinical MobileNet-V3
    const localStart = Date.now();
    const localResult = await this.fallbackLocalMobileNet(rawBuffer, categoryHint);
    localResult.latencyMs = Date.now() - startTime;
    console.log(`🩺 [CloudVisionClassifier] Local fallback completed: "${localResult.condition}" (${(localResult.confidence * 100).toFixed(1)}%) in ${Date.now() - localStart}ms (Total: ${localResult.latencyMs}ms)`);
    return localResult;
  }

  /**
   * Invokes Qwen 2.5-VL 72B via Hugging Face Router endpoint
   */
  private static async callCloudVisionModel(
    rawBuffer: Buffer,
    categoryHint?: ClinicalImageCategory
  ): Promise<CloudVisionClassificationResult> {
    const token = process.env.HF_TOKEN!.trim();

    // Standardize & resize image to max 512x512 JPEG to reduce token usage and network latency
    const normalizedJpeg = await sharp(rawBuffer)
      .resize({ width: 512, height: 512, fit: 'inside', withoutEnlargement: true })
      .jpeg({ quality: 85 })
      .toBuffer();

    const base64Image = normalizedJpeg.toString('base64');

    const systemPrompt = `You are a senior clinical diagnostician and computer vision expert in tele-triage.
Analyze this medical photograph with high clinical precision.
The image may depict:
1. Ophthalmology (e.g., Acute Conjunctivitis, Subconjunctival Hemorrhage, Blepharitis, Hordeolum/Stye, Scleral Icterus, Corneal Abrasion).
2. Trauma & Wound Care (e.g., Lacerations, Incised Wounds, Abrasions, Thermal/Chemical Burns, Punctures, Surgical Incision Dehiscence, Ulcers).
3. Dermatology (e.g., Atopic Dermatitis, Contact Dermatitis, Psoriasis, Urticaria, Cellulitis, Melanocytic Nevus, Impetigo, Acne Vulgaris).
4. Oral & Throat (e.g., Aphthous Stomatitis, Streptococcal Pharyngitis, Oral Candidiasis, Herpes Labialis, Tonsillitis).
5. General Clinical Manifestations (e.g., Peripheral Edema, Hematoma, Localized Erythema).

Category hint from patient triage intake: ${categoryHint || 'General clinical triage'}.

Evaluate the photograph and output STRICT JSON matching this schema:
{
  "condition": string, // Most probable specific medical condition (e.g., "Acute Bacterial Conjunctivitis", "Superficial Dermal Laceration", "Subconjunctival Hemorrhage", "Second-Degree Thermal Burn")
  "anatomicalSite": string, // e.g., "Left Eye / Conjunctival Sclera", "Right Palmar Forearm", "Oral Mucosa", "Facial / Periorbital"
  "severity": "BENIGN" | "MILD" | "MODERATE" | "SEVERE" | "CRITICAL",
  "confidence": number, // [0.0 - 1.0]
  "findings": string[], // 2 to 5 specific objective clinical visual signs
  "differentialDiagnoses": string[], // 2 to 4 key alternative differential diagnoses
  "clinicalDescription": string, // 2-3 sentence rigorous clinical summary of visual presentation
  "isEmergencyAlert": boolean, // True if active severe hemorrhage, sight-threatening ocular trauma, necrotizing infection, or full thickness burn
  "emergencyDirective": string | null, // If emergency, concise immediate clinical guidance
  "recommendedAction": string // Triage recommendation (e.g., "Urgent Ophthalmology evaluation", "Wound irrigation and topical antibiotic coverage", "Preserve dry dressing and seek urgent care")
}
Do not include markdown or explanations. Output valid JSON only.`;

    const res = await fetch(this.HF_ROUTER_URL, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        model: this.CLOUD_MODEL_ID,
        messages: [
          {
            role: 'system',
            content: systemPrompt
          },
          {
            role: 'user',
            content: [
              {
                type: 'text',
                text: 'Analyze this clinical medical photograph and provide differential diagnosis and severity triage.'
              },
              {
                type: 'image_url',
                image_url: {
                  url: `data:image/jpeg;base64,${base64Image}`
                }
              }
            ]
          }
        ],
        temperature: 0.1,
        max_tokens: 600,
        response_format: { type: 'json_object' }
      })
    });

    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`HF Router HTTP ${res.status}: ${errText.slice(0, 300)}`);
    }

    const data = await res.json();
    const rawContent = data.choices?.[0]?.message?.content || '{}';
    const parsed = this.cleanAndParseJSON(rawContent);

    // Validate and sanitize parsed fields
    const validSeverities = ['BENIGN', 'MILD', 'MODERATE', 'SEVERE', 'CRITICAL'] as const;
    const severity = validSeverities.includes(parsed.severity) ? parsed.severity : 'MODERATE';
    const confidence = Math.max(0.1, Math.min(1.0, Number(parsed.confidence) || 0.85));

    return {
      condition: parsed.condition || 'Clinical Image Presentation',
      anatomicalSite: parsed.anatomicalSite || 'Integumentary / Superficial',
      severity,
      confidence,
      findings: Array.isArray(parsed.findings) && parsed.findings.length > 0 
        ? parsed.findings 
        : ['Visual erythema present', 'Localized tissue presentation'],
      differentialDiagnoses: Array.isArray(parsed.differentialDiagnoses) && parsed.differentialDiagnoses.length > 0
        ? parsed.differentialDiagnoses
        : [parsed.condition || 'Dermatological Presentation'],
      clinicalDescription: parsed.clinicalDescription || 'Clinical photograph exhibits localized inflammatory presentation.',
      isEmergencyAlert: Boolean(parsed.isEmergencyAlert) || severity === 'CRITICAL',
      emergencyDirective: parsed.emergencyDirective || undefined,
      recommendedAction: parsed.recommendedAction || 'Seek clinical consultation if symptoms worsen.',
      source: 'QWEN_VL_72B',
      latencyMs: 0
    };
  }

  /**
   * Local MobileNet-V3 Fallback mapping
   */
  private static async fallbackLocalMobileNet(
    rawBuffer: Buffer,
    categoryHint?: ClinicalImageCategory
  ): Promise<CloudVisionClassificationResult> {
    const tfResult = await VisionDiagnosticService.analyzeImage(rawBuffer);

    let condition = 'Superficial Erythema / Dermatitis';
    let anatomicalSite = 'Integumentary Surface';
    let severity: 'BENIGN' | 'MILD' | 'MODERATE' | 'SEVERE' | 'CRITICAL' = 'MODERATE';
    let isEmergencyAlert = false;

    switch (tfResult.predictedCategory) {
      case 'Severe/Emergency':
        severity = 'CRITICAL';
        isEmergencyAlert = true;
        condition = categoryHint === 'CONJUNCTIVITIS_EYE' 
          ? 'Acute Severe Ocular Inflammation / Trauma'
          : categoryHint === 'WOUND_HEALING'
          ? 'Deep Tissue Laceration / Trauma'
          : 'Severe Ulcerative Tissue Lesion';
        break;
      case 'Acute Infection/Lesion':
        severity = 'MODERATE';
        condition = categoryHint === 'CONJUNCTIVITIS_EYE'
          ? 'Acute Conjunctivitis / Scleral Injection'
          : categoryHint === 'WOUND_HEALING'
          ? 'Acute Wound / Cut with Active Inflammation'
          : categoryHint === 'ORAL_THROAT_INFECTION'
          ? 'Acute Oral / Mucosal Infection'
          : 'Acute Inflammatory Skin Lesion';
        break;
      case 'Mild Inflammation':
        severity = 'MILD';
        condition = 'Mild Superficial Erythema';
        break;
      case 'Normal/Benign':
      default:
        severity = 'BENIGN';
        condition = 'Benign / Normal Tissue Presentation';
        break;
    }

    if (categoryHint === 'CONJUNCTIVITIS_EYE') anatomicalSite = 'Ocular / Periorbital';
    if (categoryHint === 'ORAL_THROAT_INFECTION') anatomicalSite = 'Oral Mucosa / Oropharynx';
    if (categoryHint === 'WOUND_HEALING') anatomicalSite = 'Cutaneous Tissue (Trauma Site)';

    return {
      condition,
      anatomicalSite,
      severity,
      confidence: tfResult.confidence,
      findings: [
        `Convolutional feature mapping: ${tfResult.predictedCategory} (${(tfResult.confidence * 100).toFixed(1)}% certainty)`,
        `Visual presentation processed by local MobileNet-V3 CNN backbone`
      ],
      differentialDiagnoses: [condition, 'Contact Dermatitis', 'Localized Inflammatory Reaction'],
      clinicalDescription: `Automated deep learning assessment classifies visual features as ${tfResult.predictedCategory} with ${(tfResult.confidence * 100).toFixed(1)}% model certainty.`,
      isEmergencyAlert,
      recommendedAction: isEmergencyAlert 
        ? 'Urgent clinical evaluation recommended.' 
        : 'Monitor symptoms and maintain clean dressing or hygiene.',
      source: 'LOCAL_MOBILENET_V3',
      latencyMs: tfResult.processingTimeMs
    };
  }

  private static cleanAndParseJSON(text: string): any {
    let cleaned = text.trim();
    if (cleaned.startsWith('```json')) cleaned = cleaned.substring(7);
    if (cleaned.startsWith('```')) cleaned = cleaned.substring(3);
    if (cleaned.endsWith('```')) cleaned = cleaned.substring(0, cleaned.length - 3);
    cleaned = cleaned.trim();
    try {
      return JSON.parse(cleaned);
    } catch (_) {
      const match = cleaned.match(/\{[\s\S]*\}/);
      if (match) return JSON.parse(match[0]);
      throw new Error(`Cannot parse JSON: ${text.slice(0, 100)}`);
    }
  }
}
