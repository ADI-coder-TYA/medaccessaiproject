import { VectorAssembler } from './vectorAssembler.js';
import { MultimodalFusionModel, MultimodalPredictionOutput } from './MultimodalFusionModel.js';
import { VisionDiagnosticService } from '../vision/VisionDiagnosticService.js';
import { AudioFeatureExtractor, CoughClassifier, CoughClassificationResult } from '../audio/index.js';
import { PhysiologicalRedFlagSentinel } from '../vitals/PhysiologicalRedFlagSentinel.js';
import {
  SymptomInputPayload,
  MultimodalRiskResult,
  ClinicalRiskLevel,
  ClinicalRiskTier,
  DifferentialDiagnosis
} from './types.js';

export interface AssessMultimodalRiskOptions {
  imageBuffer?: Buffer | Uint8Array | string | null;
  visualEmbeddings?: number[] | null;
  visionFindings?: any[];
  audioBuffer?: Buffer | Uint8Array | string | null;
  audioFeatures?: number[] | null;
  audioClassification?: CoughClassificationResult | null;
  symptomData?: Partial<SymptomInputPayload> | null;
  patientVitals?: any;
  mcSamples?: number;
}

export interface RedFlagEvaluation {
  triggered: boolean;
  reasons: string[];
  enforcedFloor: number | null;
  isRespiratoryRedFlag?: boolean;
}

/**
 * Evaluates the Deterministic Clinical Safety Net.
 * Enforces a minimum risk score floor (>= 0.85) and 'Critical Referral' tier
 * if severe red-flag symptoms or critical vital sign derangements are present.
 */
export function evaluateClinicalSafetyNet(
  symptomData?: Partial<SymptomInputPayload> | null,
  vitals?: any,
  audioClassification?: CoughClassificationResult | null
): RedFlagEvaluation {
  const reasons: string[] = [];
  const mergedVitals = { ...(symptomData?.vitals || {}), ...(vitals || {}) };

  // 1. Extreme Pain (Pain = 10 / 10)
  const pain = Number(symptomData?.painScale) || 0;
  if (pain >= 10) {
    reasons.push('Extreme Pain Score (10/10) reported by patient');
  }

  // 2. High Grade Hyperpyrexia (Temp >= 40.0 C) or Severe Hypothermia (<= 34.0 C)
  const temp = Number(mergedVitals.temperatureCelsius);
  if (!isNaN(temp) && temp > 0) {
    if (temp >= 40.0) {
      reasons.push(`Hyperpyrexia critical threshold exceeded (${temp.toFixed(1)}°C >= 40.0°C)`);
    } else if (temp <= 34.0) {
      reasons.push(`Severe Hypothermia critical threshold (${temp.toFixed(1)}°C <= 34.0°C)`);
    }
  }

  // 3. Physiological Vitals & rPPG Red-Flag Sentinel Evaluation
  const spo2 = Number(mergedVitals.oxygenSaturation);
  const hr = Number(mergedVitals.heartRate);
  const rr = Number(mergedVitals.respirationRate);
  const hrv = Number(mergedVitals.hrvRmssdMs);

  const vitalsAlerts = PhysiologicalRedFlagSentinel.evaluateVitals({
    heartRate: !isNaN(hr) && hr > 0 ? hr : undefined,
    oxygenSaturation: !isNaN(spo2) && spo2 > 0 ? spo2 : undefined,
    respirationRate: !isNaN(rr) && rr > 0 ? rr : undefined,
    hrvRmssdMs: !isNaN(hrv) && hrv > 0 ? hrv : undefined
  });

  for (const alert of vitalsAlerts) {
    if (alert.severity === 'CRITICAL_OVERRIDE') {
      reasons.push(alert.clinicalDirective);
    }
  }

  // 5. Critical Symptom Red-Flag Keywords
  const symptomsText = [
    ...(symptomData?.symptoms || []),
    symptomData?.bodyLocation || '',
    symptomData?.additionalNotes || ''
  ].join(' ').toLowerCase();

  if (symptomsText.includes('chest pain') || symptomsText.includes('angina') || symptomsText.includes('myocardial')) {
    reasons.push('Acute Chest Pain present (High Risk Cardiac/Pulmonary Red Flag)');
  }

  if (symptomsText.includes('shortness of breath') || symptomsText.includes('cannot breathe') || symptomsText.includes('severe dyspnea')) {
    if (pain >= 7 || (hr && hr > 110) || (spo2 && spo2 < 93)) {
      reasons.push('Acute Respiratory Distress with associated physiological distress');
    }
  }

  if (symptomsText.includes('loss of consciousness') || symptomsText.includes('syncope') || symptomsText.includes('unresponsive')) {
    reasons.push('Neurological emergency indicator: Altered consciousness / syncope reported');
  }

  if (symptomsText.includes('stiff neck') && (temp && temp >= 38.5)) {
    reasons.push('Meningeal irritation signs: Stiff neck with high fever');
  }

  if (symptomsText.includes('anaphylaxis') || (symptomsText.includes('difficulty swallowing') && symptomsText.includes('wheezing'))) {
    reasons.push('Airway compromise warning: Signs of systemic anaphylaxis / laryngeal edema');
  }

  const hasCriticalRedFlag = reasons.length > 0;

  // 6. Wheeze / Stridor Red-Flag Floor (>= 0.75) per Technical Guardrail 3
  let isRespiratoryRedFlag = false;
  if (audioClassification) {
    const isWheeze = audioClassification.predictedCategory === 'Wheeze/Stridor';
    const wheezeConfidence = audioClassification.probabilities?.wheezeStridor ?? audioClassification.confidence ?? 0;
    if (isWheeze && wheezeConfidence >= 0.70) {
      isRespiratoryRedFlag = true;
      reasons.push(
        `Respiratory Red Flag: Wheeze/Stridor detected with ${(wheezeConfidence * 100).toFixed(1)}% confidence (>= 70% threshold)`
      );
    }
  }

  const triggered = reasons.length > 0;
  let enforcedFloor: number | null = null;
  if (hasCriticalRedFlag) {
    enforcedFloor = 0.85;
  } else if (isRespiratoryRedFlag) {
    enforcedFloor = 0.75;
  }

  return {
    triggered,
    reasons,
    enforcedFloor,
    isRespiratoryRedFlag
  };
}

/**
 * Primary Multimodal Health Risk Assessment Inference Wrapper.
 *
 * Coordinates:
 * 1. Computer Vision Feature Extraction (or text-only prior handling if no image)
 * 2. Strict Min-Max [0, 1] Vector Assembly (168-d tensor)
 * 3. Monte Carlo Dropout TF.js Inference (N=10 passes for epistemic uncertainty)
 * 4. Deterministic Clinical Safety Net enforcement (floor >= 0.85 & Critical Referral)
 */
export async function assessMultimodalRisk(
  imageBufferOrOptions?: Buffer | Uint8Array | string | AssessMultimodalRiskOptions | null,
  symptomDataArg?: Partial<SymptomInputPayload> | null,
  patientVitalsArg?: any,
  mcSamplesArg = 10
): Promise<MultimodalRiskResult & {
  concatenatedVector: number[];
  isTextOnlyScreening: boolean;
  visionFindings?: any[];
  audioFeatures?: number[] | null;
  audioClassification?: CoughClassificationResult | null;
}> {
  let imageBuffer: Buffer | Uint8Array | string | null | undefined;
  let visualEmbeddings: number[] | null = null;
  let visionFindings: any[] | undefined = undefined;
  let audioBuffer: Buffer | Uint8Array | string | null | undefined;
  let audioFeatures: number[] | null = null;
  let audioClassification: CoughClassificationResult | null = null;
  let symptomData: Partial<SymptomInputPayload> | null | undefined;
  let patientVitals: any;
  let mcSamples = mcSamplesArg;

  if (
    imageBufferOrOptions &&
    typeof imageBufferOrOptions === 'object' &&
    !Buffer.isBuffer(imageBufferOrOptions) &&
    !(imageBufferOrOptions instanceof Uint8Array) &&
    ('symptomData' in imageBufferOrOptions || 'imageBuffer' in imageBufferOrOptions || 'visualEmbeddings' in imageBufferOrOptions || 'audioBuffer' in imageBufferOrOptions || 'audioFeatures' in imageBufferOrOptions)
  ) {
    const opts = imageBufferOrOptions as AssessMultimodalRiskOptions;
    imageBuffer = opts.imageBuffer;
    visualEmbeddings = opts.visualEmbeddings || null;
    visionFindings = opts.visionFindings;
    audioBuffer = opts.audioBuffer;
    audioFeatures = opts.audioFeatures || null;
    audioClassification = opts.audioClassification || null;
    symptomData = opts.symptomData;
    patientVitals = opts.patientVitals;
    mcSamples = opts.mcSamples || mcSamplesArg;
  } else {
    imageBuffer = imageBufferOrOptions as Buffer | Uint8Array | string | null | undefined;
    symptomData = symptomDataArg;
    patientVitals = patientVitalsArg;
    mcSamples = mcSamplesArg;
  }

  let isTextOnlyScreening = !visualEmbeddings;

  // 1. Vision Feature Extraction or Text-Only Prior Handling
  if (imageBuffer && !visualEmbeddings) {
    try {
      let rawBuf: Buffer;
      if (typeof imageBuffer === 'string') {
        if (imageBuffer.startsWith('data:')) {
          const base64Data = imageBuffer.split(',')[1];
          rawBuf = Buffer.from(base64Data, 'base64');
        } else {
          rawBuf = Buffer.from(imageBuffer, 'utf-8');
        }
      } else if (Buffer.isBuffer(imageBuffer)) {
        rawBuf = imageBuffer;
      } else {
        rawBuf = Buffer.from(imageBuffer);
      }

      if (rawBuf.length > 0) {
        const visionResult = await VisionDiagnosticService.analyzeImage(rawBuf);
        visualEmbeddings = visionResult.bottleneckEmbedding;
        visionFindings = [
          {
            className: visionResult.predictedCategory,
            probability: visionResult.confidence
          }
        ];
        isTextOnlyScreening = false;
      }
    } catch (visionErr) {
      console.warn(`⚠️ [assessMultimodalRisk] Vision processing fallback to text-only prior: ${visionErr}`);
      visualEmbeddings = null;
      isTextOnlyScreening = true;
    }
  }

  // 2. Audio Feature Extraction & Cough Classification
  if (audioBuffer && !audioFeatures) {
    try {
      let rawAudioBuf: Buffer;
      if (typeof audioBuffer === 'string') {
        const base64Data = audioBuffer.startsWith('data:') ? audioBuffer.split(',')[1] : audioBuffer;
        rawAudioBuf = Buffer.from(base64Data, 'base64');
      } else if (Buffer.isBuffer(audioBuffer)) {
        rawAudioBuf = audioBuffer;
      } else {
        rawAudioBuf = Buffer.from(audioBuffer);
      }

      if (rawAudioBuf.length > 0) {
        console.log(`🎙️ [assessMultimodalRisk] Extracting 16 acoustic features from raw buffer (${rawAudioBuf.length} bytes)...`);
        const audioResult = await AudioFeatureExtractor.extractFeatures(rawAudioBuf);
        audioFeatures = audioResult.featureVector;
        if (!audioClassification) {
          audioClassification = await CoughClassifier.classify(audioFeatures);
        }
        console.log(`🩺 [assessMultimodalRisk] Fused acoustic biomarker: "${audioClassification?.predictedCategory}" (${((audioClassification?.confidence || 0) * 100).toFixed(1)}%) | RedFlag: ${audioClassification?.isRedFlagRespiratory}`);
      }
    } catch (audioErr) {
      console.warn(`⚠️ [assessMultimodalRisk] Audio processing fallback to neutral prior: ${audioErr}`);
      audioFeatures = null;
    }
  } else if (audioFeatures && !audioClassification) {
    try {
      audioClassification = await CoughClassifier.classify(audioFeatures);
    } catch (clfErr) {
      console.warn(`⚠️ [assessMultimodalRisk] Cough classification error: ${clfErr}`);
    }
  }

  // 3. Strict Min-Max Feature Vector Assembly (184 dimensions)
  // Text-only automatically fills 128-d vector with uniform 1 / sqrt(128)
  // No-audio automatically fills 16-d vector with uniform 1 / sqrt(16) = 0.25
  const assembled = VectorAssembler.assembleVector(visualEmbeddings, symptomData, patientVitals, audioFeatures);
  const concatenatedVector = assembled.concatenatedVector;

  // 4. Monte Carlo Dropout Inference in TensorFlow.js
  const mcPrediction: MultimodalPredictionOutput = await MultimodalFusionModel.predictWithMCDropout(
    concatenatedVector,
    mcSamples
  );

  // 5. Deterministic Clinical Safety Net (includes Wheeze/Stridor red-flag floor >= 0.75)
  const safetyNet = evaluateClinicalSafetyNet(symptomData, patientVitals, audioClassification);

  let finalRiskScore = mcPrediction.meanScore;
  let finalRiskTier: ClinicalRiskTier = mcPrediction.predictedTier;
  let finalRiskLevel: ClinicalRiskLevel = 'LOW';

  if (safetyNet.triggered) {
    const floor = safetyNet.enforcedFloor ?? 0.85;
    finalRiskScore = Math.max(floor, mcPrediction.meanScore);
    if (safetyNet.enforcedFloor === 0.85) {
      finalRiskTier = 'Critical Referral';
      finalRiskLevel = 'CRITICAL';
    } else {
      // Wheeze / Stridor floor (>= 0.75) per Technical Guardrail 3
      finalRiskLevel = 'CRITICAL';
      if (finalRiskTier !== 'Critical Referral') {
        finalRiskTier = 'Moderate Need';
      }
    }
  } else {
    // Map predicted tier and score to clinical risk level
    if (finalRiskTier === 'Critical Referral' || finalRiskScore >= 0.75) {
      finalRiskLevel = 'CRITICAL';
    } else if (finalRiskTier === 'Moderate Need' || finalRiskScore >= 0.50) {
      finalRiskLevel = 'HIGH';
    } else if (finalRiskScore >= 0.25) {
      finalRiskLevel = 'MODERATE';
    } else {
      finalRiskLevel = 'LOW';
    }
  }

  // 6. Differential Diagnoses & Clinical Recommendations
  const differentialDiagnoses = generateDifferentialDiagnoses(
    symptomData,
    visionFindings,
    finalRiskScore
  );

  // Complement differential diagnoses with cough/wheeze acoustic pattern if detected
  if (audioClassification && audioClassification.predictedCategory !== 'Normal Respiratory') {
    const category = audioClassification.predictedCategory;
    const urgency = category === 'Wheeze/Stridor' ? 'EMERGENCY' : 'PROMPT_CARE';
    differentialDiagnoses.unshift({
      condition: `Acoustic finding: ${category}`,
      probability: audioClassification.confidence,
      urgency
    });
  }

  const primaryDiagnosis = differentialDiagnoses[0]?.condition || 'Acute Symptom Presentation';
  const clinicalRecommendations = generateClinicalRecommendations(
    finalRiskLevel,
    finalRiskTier,
    safetyNet,
    primaryDiagnosis
  );

  return {
    riskScore: Number(finalRiskScore.toFixed(4)),
    riskLevel: finalRiskLevel,
    riskTier: finalRiskTier,
    tierProbabilities: mcPrediction.tierProbabilities,
    uncertaintyBounds: {
      confidence: mcPrediction.confidence,
      ciLower: mcPrediction.ciLower,
      ciUpper: mcPrediction.ciUpper,
      epistemicVariance: mcPrediction.epistemicVariance,
      monteCarloSamples: mcPrediction.monteCarloSamples
    },
    primaryDiagnosis,
    differentialDiagnoses,
    clinicalRecommendations,
    featureWeights: {
      visualContribution: isTextOnlyScreening ? 0.0 : 0.40,
      symptomContribution: isTextOnlyScreening ? 0.55 : 0.30,
      vitalsContribution: isTextOnlyScreening ? 0.20 : 0.15,
      demographicContribution: isTextOnlyScreening ? 0.10 : 0.05,
      audioContribution: audioFeatures ? 0.10 : 0.0
    },
    requiresImmediatePhysicianReview: finalRiskLevel === 'CRITICAL' || safetyNet.triggered,
    safetyNet: {
      triggered: safetyNet.triggered,
      reasons: safetyNet.reasons,
      enforcedFloor: safetyNet.enforcedFloor
    },
    concatenatedVector,
    isTextOnlyScreening,
    visionFindings,
    audioFeatures,
    audioClassification
  };
}

function generateDifferentialDiagnoses(
  symptomData?: Partial<SymptomInputPayload> | null,
  visionFindings?: any[],
  riskScore = 0.5
): DifferentialDiagnosis[] {
  const differentials: DifferentialDiagnosis[] = [];

  if (visionFindings && visionFindings.length > 0) {
    const top = visionFindings[0];
    differentials.push({
      condition: top.className || 'Dermatological / Tissue Finding',
      probability: Number(Math.min(0.95, top.probability + 0.1).toFixed(2)),
      urgency: riskScore >= 0.75 ? 'EMERGENCY' : riskScore >= 0.5 ? 'PROMPT_CARE' : 'ROUTINE'
    });
  }

  const body = (symptomData?.bodyLocation || '').toLowerCase();
  const symptoms = (symptomData?.symptoms || []).join(' ').toLowerCase();

  if (body.includes('chest') || symptoms.includes('chest pain')) {
    differentials.push({ condition: 'Acute Coronary Syndrome Rule-Out', probability: 0.88, urgency: 'EMERGENCY' });
    differentials.push({ condition: 'Costochondritis / Musculoskeletal Chest Wall Strain', probability: 0.45, urgency: 'PROMPT_CARE' });
  } else if (body.includes('throat') || body.includes('mouth') || symptoms.includes('difficulty swallowing')) {
    differentials.push({ condition: 'Acute Streptococcal Pharyngitis', probability: 0.76, urgency: 'PROMPT_CARE' });
    differentials.push({ condition: 'Peritonsillar Abscess Evaluation', probability: 0.38, urgency: 'PROMPT_CARE' });
  } else if (body.includes('skin') || symptoms.includes('rash') || symptoms.includes('erythema')) {
    differentials.push({ condition: 'Acute Contact Dermatitis / Eczematous Flare', probability: 0.72, urgency: 'ROUTINE' });
    differentials.push({ condition: 'Infectious Cellulitis', probability: 0.44, urgency: 'PROMPT_CARE' });
  } else if (body.includes('abdomen') || symptoms.includes('nausea')) {
    differentials.push({ condition: 'Acute Gastroenteritis', probability: 0.68, urgency: 'ROUTINE' });
    differentials.push({ condition: 'Peritoneal Irritation Rule-Out', probability: 0.32, urgency: 'PROMPT_CARE' });
  } else {
    differentials.push({ condition: 'Non-Specific Acute Malaise', probability: 0.55, urgency: 'ROUTINE' });
  }

  return differentials;
}

function generateClinicalRecommendations(
  riskLevel: ClinicalRiskLevel,
  riskTier: ClinicalRiskTier,
  safetyNet: RedFlagEvaluation,
  primaryDiagnosis: string
): string[] {
  const recs: string[] = [];

  if (safetyNet.triggered) {
    recs.push('EMERGENCY SAFETY OVERRIDE: Severe clinical red flags detected.');
    safetyNet.reasons.forEach(r => recs.push(`Trigger: ${r}`));
    recs.push('Seek immediate emergency medical care (dial 911 or visit the nearest Emergency Department).');
    recs.push('Do not attempt self-transportation if feeling lightheaded or having active chest pain.');
    return recs;
  }

  switch (riskLevel) {
    case 'CRITICAL':
      recs.push('URGENT: High clinical severity requires immediate physician evaluation.');
      recs.push('Proceed to urgent care or emergency room if symptoms rapidly progress.');
      recs.push('Keep a written log of onset, vitals, and all taken medications.');
      break;
    case 'HIGH':
      recs.push(`Prioritize an in-person or same-day clinical consult for ${primaryDiagnosis}.`);
      recs.push('Monitor vital signs (temperature, pulse) every 4 hours.');
      recs.push('If swelling spreads or fever exceeds 38.5°C, escalate to emergency triage.');
      break;
    case 'MODERATE':
      recs.push('Monitor symptoms over the next 24 to 48 hours.');
      recs.push('Maintain hydration, rest, and follow symptomatic supportive care.');
      recs.push('Re-screen in MedAccess AI if symptoms worsen or fail to improve.');
      break;
    case 'LOW':
    default:
      recs.push('Symptoms align with mild, likely self-limiting conditions.');
      recs.push('Continue normal hygiene, rest, and hydration.');
      recs.push('Contact a healthcare provider if symptoms persist beyond 7 days.');
      break;
  }

  return recs;
}
