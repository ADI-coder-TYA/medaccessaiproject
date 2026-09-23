import {
  SymptomInputPayload,
  MultimodalRiskResult,
  ClinicalRiskLevel,
  UncertaintyBounds,
  DifferentialDiagnosis
} from './types.js';
import { VisionEmbeddingResult } from '../vision/types.js';
import { assessMultimodalRisk } from './assessMultimodalRisk.js';
import { MultimodalFusionModel } from './MultimodalFusionModel.js';

export class MultimodalRiskNetwork {
  private static isModelLoaded = false;
  private static readonly MC_DROPOUT_RUNS = 10;

  public static async initialize(): Promise<void> {
    if (this.isModelLoaded) return;
    await MultimodalFusionModel.loadOrBootstrapModel();
    this.isModelLoaded = true;
    console.log('🧬 [Diagnostics Fusion] Multimodal Risk Fusion Neural Network initialized');
  }

  /**
   * Fuses vision embedding vector (128-d), structured symptoms, vitals, and audio biomarkers into a unified clinical risk assessment.
   */
  public static async assessRisk(
    symptoms: SymptomInputPayload,
    visionResult?: VisionEmbeddingResult,
    audioOptions?: { audioBuffer?: Buffer; audioFeatures?: number[] }
  ): Promise<MultimodalRiskResult> {
    await this.initialize();

    return assessMultimodalRisk({
      visualEmbeddings: visionResult?.featureVector || null,
      visionFindings: visionResult?.topFindings,
      symptomData: symptoms,
      patientVitals: symptoms.vitals,
      audioBuffer: audioOptions?.audioBuffer,
      audioFeatures: audioOptions?.audioFeatures,
      mcSamples: this.MC_DROPOUT_RUNS
    });
  }


  private static computeStructuredSymptomScore(s: SymptomInputPayload): number {
    let score = (s.painScale / 10.0) * 0.4; // Pain contributes up to 0.40

    // Duration escalation (e.g. chronic worsening vs acute onset)
    if (s.durationDays > 14) score += 0.2;
    else if (s.durationDays > 3) score += 0.1;

    // Red flag symptom keywords
    const redFlags = ['chest pain', 'shortness of breath', 'hemorrhage', 'loss of consciousness', 'blurry vision', 'stiff neck'];
    const symptomsLower = s.symptoms.map(sym => sym.toLowerCase());

    const hasRedFlag = redFlags.some(flag => symptomsLower.some(sym => sym.includes(flag)));
    if (hasRedFlag) score += 0.35;

    score += Math.min(0.25, s.symptoms.length * 0.05);

    return Math.min(1.0, Math.max(0.05, score));
  }

  private static computeVitalsDeviationScore(s: SymptomInputPayload): number {
    if (!s.vitals) return 0.2; // Baseline nominal vitals

    let deviation = 0.0;

    // Heart rate (nominal 60 - 100 bpm)
    if (s.vitals.heartRate) {
      if (s.vitals.heartRate > 120 || s.vitals.heartRate < 50) deviation += 0.35;
      else if (s.vitals.heartRate > 100 || s.vitals.heartRate < 55) deviation += 0.15;
    }

    // Temperature (nominal 36.5 - 37.5 C)
    if (s.vitals.temperatureCelsius) {
      if (s.vitals.temperatureCelsius >= 39.0 || s.vitals.temperatureCelsius <= 35.0) deviation += 0.40;
      else if (s.vitals.temperatureCelsius >= 38.0) deviation += 0.20;
    }

    // Blood Pressure (systolic nominal < 130)
    if (s.vitals.systolicBP) {
      if (s.vitals.systolicBP >= 160 || s.vitals.systolicBP <= 90) deviation += 0.35;
      else if (s.vitals.systolicBP >= 140) deviation += 0.15;
    }

    // Oxygen Saturation (nominal >= 95%)
    if (s.vitals.oxygenSaturation) {
      if (s.vitals.oxygenSaturation < 90) deviation += 0.60;
      else if (s.vitals.oxygenSaturation < 94) deviation += 0.30;
    }

    return Math.min(1.0, Math.max(0.05, deviation));
  }

  private static computeVisionScore(vision?: VisionEmbeddingResult): number {
    if (!vision) return 0.0;
    // Derive risk weight from classification confidence & significance
    const topFinding = vision.topFindings[0];
    if (!topFinding) return 0.3;

    switch (topFinding.clinicalSignificance) {
      case 'HIGH_ALERT':
        return 0.85 * topFinding.confidence;
      case 'MODERATE_SUSPICION':
        return 0.60 * topFinding.confidence;
      case 'LOW_RISK':
        return 0.30 * topFinding.confidence;
      case 'BENIGN':
      default:
        return 0.15 * topFinding.confidence;
    }
  }

  /**
   * Simulates Monte Carlo Dropout inference over multiple stochastic forward passes.
   */
  private static runMonteCarloDropoutInference(baseScore: number, runs: number): { mean: number; variance: number; stdDev: number } {
    const samples: number[] = [];
    const dropoutRate = 0.08; // 8% stochastic jitter modeling neural dropout

    for (let i = 0; i < runs; i++) {
      const noise = (Math.sin(i * 1.7) * 0.5 + Math.cos(i * 3.1) * 0.5) * dropoutRate;
      const sampledScore = Math.min(1.0, Math.max(0.0, baseScore + noise));
      samples.push(sampledScore);
    }

    const mean = samples.reduce((acc, v) => acc + v, 0) / runs;
    const variance = samples.reduce((acc, v) => acc + Math.pow(v - mean, 2), 0) / (runs - 1);
    const stdDev = Math.sqrt(variance);

    return { mean, variance, stdDev };
  }

  private static mapScoreToRiskLevel(score: number, painScale: number): ClinicalRiskLevel {
    if (score >= 0.75 || painScale >= 9) return 'CRITICAL';
    if (score >= 0.50 || painScale >= 6) return 'HIGH';
    if (score >= 0.25 || painScale >= 3) return 'MODERATE';
    return 'LOW';
  }

  private static generateDifferentialDiagnoses(
    symptoms: SymptomInputPayload,
    vision?: VisionEmbeddingResult,
    riskScore?: number
  ): DifferentialDiagnosis[] {
    const differentials: DifferentialDiagnosis[] = [];

    if (vision && vision.predictedCondition) {
      differentials.push({
        condition: vision.predictedCondition,
        probability: Number((0.65 + (riskScore || 0) * 0.2).toFixed(2)),
        urgency: (riskScore || 0) > 0.6 ? 'PROMPT_CARE' : 'ROUTINE'
      });
    }

    // Add contextual symptom-based diagnoses
    const body = (symptoms.bodyLocation || '').toLowerCase();
    if (body.includes('throat') || body.includes('mouth')) {
      differentials.push({ condition: 'Streptococcal Pharyngitis', probability: 0.74, urgency: 'PROMPT_CARE' });
      differentials.push({ condition: 'Viral Upper Respiratory Pharyngitis', probability: 0.58, urgency: 'ROUTINE' });
    } else if (body.includes('skin') || body.includes('arm') || body.includes('leg') || body.includes('face')) {
      differentials.push({ condition: 'Eczematous / Contact Dermatitis', probability: 0.71, urgency: 'ROUTINE' });
      differentials.push({ condition: 'Cellulitis / Localized Secondary Infection', probability: 0.42, urgency: 'PROMPT_CARE' });
    } else if (body.includes('eye')) {
      differentials.push({ condition: 'Acute Adenoviral Conjunctivitis', probability: 0.78, urgency: 'ROUTINE' });
      differentials.push({ condition: 'Bacterial Keratoconjunctivitis', probability: 0.35, urgency: 'PROMPT_CARE' });
    } else {
      differentials.push({ condition: 'Acute Somatic Discomfort', probability: 0.62, urgency: 'ROUTINE' });
    }

    return differentials;
  }

  private static buildClinicalRecommendations(
    level: ClinicalRiskLevel,
    symptoms: SymptomInputPayload,
    primaryCondition?: string
  ): string[] {
    const recs: string[] = [];

    switch (level) {
      case 'CRITICAL':
        recs.push('Seek immediate emergency medical attention or proceed to nearest Urgent Care / Emergency Dept.');
        recs.push('Avoid strenuous activity and do not drive yourself if experiencing dizziness or severe pain.');
        recs.push('Prepare a list of current medications and allergies for emergency clinical intake.');
        break;

      case 'HIGH':
        recs.push(`Schedule an in-person or high-priority telemedicine consult within 24 hours for ${primaryCondition || 'evaluation'}.`);
        recs.push('Track vitals (temperature and heart rate) every 4 to 6 hours.');
        recs.push('If swelling, progressive redness, or fever > 38.5°C develops, escalate to urgent care immediately.');
        break;

      case 'MODERATE':
        recs.push(`Monitor symptoms closely for 48 hours. Consider over-the-counter supportive therapy if approved by a pharmacist.`);
        recs.push('Maintain proper hydration and rest.');
        recs.push('Take follow-up clinical photos in consistent lighting to evaluate lesion or rash progression.');
        break;

      case 'LOW':
      default:
        recs.push('Routine monitoring. Symptoms are consistent with mild self-limiting conditions.');
        recs.push('Maintain clean hygiene around affected area and avoid harsh topicals or scratching.');
        recs.push('Re-screen in the MedAccess AI app if symptoms persist past 5-7 days.');
        break;
    }

    return recs;
  }
}
