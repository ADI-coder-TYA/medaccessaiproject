import {
  CDSSInputPayload,
  DifferentialDiagnosisCandidate,
  ICD11Concept
} from './types.js';
import { ICD11ConceptStore } from './ICD11ConceptStore.js';

export class DifferentialDiagnosisEngine {
  /**
   * Technical Guardrail 2: Softmax Temperature Scaling & Logit Clipping [-20, 20]
   * Computes normalized posterior probabilities across candidate ICD-11 entities.
   */
  public static evaluateCandidates(
    payload: CDSSInputPayload,
    temperature = 1.25
  ): DifferentialDiagnosisCandidate[] {
    const safeTemperature = Math.max(0.5, Math.min(3.0, temperature || 1.25));
    const concepts = ICD11ConceptStore.getAllConcepts();

    // Extract clinical signals from payload
    const symptomsList = (payload.symptoms?.symptoms || []).map((s) => s.toLowerCase());
    const bodyLocation = (payload.symptoms?.bodyLocation || '').toLowerCase();
    const vitals = payload.symptoms?.vitals || {};
    const riskScore = payload.multimodalRiskScore ?? 0.5;
    const coughCategory = payload.audioClassification?.predictedCategory;
    const visionFindings = payload.visionFindings || [];

    // Calculate raw logit score for each ICD-11 candidate
    const candidateScores: Array<{
      concept: ICD11Concept;
      rawLogit: number;
      matchedCriteria: string[];
      clinicalRationale: string;
    }> = [];

    for (const concept of concepts) {
      let score = 0.0;
      const matched: string[] = [];
      const criteria = concept.clinicalCriteria;

      // 1. Keyword & Symptom overlap
      for (const kw of criteria.requiredKeywords) {
        const lowerKw = kw.toLowerCase();
        if (symptomsList.some((s) => s.includes(lowerKw) || lowerKw.includes(s))) {
          score += 2.5;
          matched.push(`Symptom match: "${kw}"`);
        }
      }

      // 2. Anatomical body location alignment
      if (criteria.anatomicalLocations && criteria.anatomicalLocations.length > 0) {
        if (criteria.anatomicalLocations.some((loc) => loc.toLowerCase() === bodyLocation)) {
          score += 2.0;
          matched.push(`Anatomical correlation: "${bodyLocation}"`);
        }
      }

      // 3. Objective Vitals & rPPG threshold triggers
      if (criteria.vitalsTriggers) {
        const vt = criteria.vitalsTriggers;
        const temp = Number(vitals.temperatureCelsius);
        const hr = Number(vitals.heartRate);
        const spo2 = Number(vitals.oxygenSaturation);
        const rr = Number(vitals.respirationRate);
        const sbp = Number(vitals.systolicBP);

        if (vt.feverMinCelsius && !isNaN(temp) && temp >= vt.feverMinCelsius) {
          score += 2.2;
          matched.push(`Fever: ${temp.toFixed(1)}°C (>= ${vt.feverMinCelsius}°C)`);
        }
        if (vt.tachycardiaMinBpm && !isNaN(hr) && hr >= vt.tachycardiaMinBpm) {
          score += 2.0;
          matched.push(`Tachycardia: ${hr} BPM (>= ${vt.tachycardiaMinBpm} BPM)`);
        }
        if (vt.hypoxiaMaxSpo2 && !isNaN(spo2) && spo2 <= vt.hypoxiaMaxSpo2) {
          score += 3.5;
          matched.push(`Hypoxia: SpO2 ${spo2.toFixed(1)}% (<= ${vt.hypoxiaMaxSpo2}%)`);
        }
        if (vt.tachypneaMinBreathsPerMin && !isNaN(rr) && rr >= vt.tachypneaMinBreathsPerMin) {
          score += 2.5;
          matched.push(`Tachypnea: ${rr} breaths/min (>= ${vt.tachypneaMinBreathsPerMin})`);
        }
        if (vt.hypertensionMinSystolic && !isNaN(sbp) && sbp >= vt.hypertensionMinSystolic) {
          score += 3.0;
          matched.push(`Hypertension: Systolic ${sbp} mmHg (>= ${vt.hypertensionMinSystolic} mmHg)`);
        }
      }

      // 4. Acoustic Cough pattern alignment
      if (criteria.coughCategories && coughCategory) {
        if (criteria.coughCategories.includes(coughCategory)) {
          score += 2.8;
          matched.push(`Acoustic classifier finding: "${coughCategory}"`);
        }
      }

      // 5. Computer Vision pattern alignment
      if (criteria.visionPatterns && visionFindings.length > 0) {
        for (const finding of visionFindings) {
          if (criteria.visionPatterns.some((vp) => finding.condition.toLowerCase().includes(vp.toLowerCase()))) {
            score += 3.0 * (finding.confidence || 0.8);
            matched.push(`Visual pathology finding: "${finding.condition}"`);
          }
        }
      }

      // 6. Multimodal Risk Tier compatibility
      if (criteria.minRiskScore !== undefined) {
        if (riskScore >= criteria.minRiskScore) {
          score += 1.5;
        } else {
          score -= 1.0;
        }
      }

      // Construct explanatory rationale summary
      const clinicalRationale =
        matched.length > 0
          ? matched.slice(0, 3).join('; ')
          : 'Low baseline statistical prior across presenting clinical features';

      candidateScores.push({
        concept,
        rawLogit: score,
        matchedCriteria: matched,
        clinicalRationale
      });
    }

    // Technical Guardrail 2: Softmax Normalization Safeguard with Logit Clipping [-20, 20]
    // and Temperature Scaling (T = 1.2 - 1.5)
    const clippedAndScaledLogits = candidateScores.map((c) => {
      // 1. Clip raw logit to [-20, 20] to guarantee no exp() numerical overflow / underflow
      const clipped = Math.max(-20.0, Math.min(20.0, c.rawLogit));
      // 2. Apply temperature scaling
      return clipped / safeTemperature;
    });

    // Numerical stability trick: subtract max logit before exponentiation
    const maxScaledLogit = Math.max(...clippedAndScaledLogits);
    const expValues = clippedAndScaledLogits.map((l) => Math.exp(l - maxScaledLogit));
    const sumExp = expValues.reduce((sum, v) => sum + v, 0);

    const candidates: DifferentialDiagnosisCandidate[] = candidateScores.map((c, idx) => {
      const prob = sumExp > 0 ? expValues[idx] / sumExp : 1.0 / candidateScores.length;
      return {
        code: c.concept.code,
        title: c.concept.title,
        category: c.concept.category,
        uri: c.concept.uri,
        probability: Math.round(prob * 10000) / 10000, // 4 decimal places
        logitScore: Math.round(c.rawLogit * 100) / 100,
        matchedCriteria: c.matchedCriteria,
        clinicalRationale: c.clinicalRationale
      };
    });

    // Sort descending by posterior probability and take top 5
    candidates.sort((a, b) => b.probability - a.probability);
    return candidates.slice(0, 5);
  }
}
