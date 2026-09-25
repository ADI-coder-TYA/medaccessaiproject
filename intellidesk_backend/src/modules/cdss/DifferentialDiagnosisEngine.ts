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
    const rawSymptomsList: string[] = [
      ...(Array.isArray(payload.symptoms?.symptoms) ? payload.symptoms.symptoms : []),
      ...(Array.isArray((payload.symptoms as any)?.symptomList) ? (payload.symptoms as any).symptomList : [])
    ];
    const symptomsList = rawSymptomsList.map((s) => String(s).toLowerCase());
    const rawAnatomical = (payload as any).anatomicalLocation || (payload.symptoms as any)?.anatomicalLocation || payload.symptoms?.bodyLocation || '';
    const upperAnatomical = rawAnatomical.trim().toUpperCase();
    const lowerAnatomical = rawAnatomical.trim().toLowerCase();

    // Contextual text analysis for anatomical inference
    const contextText = [
      (payload.symptoms as any)?.primaryDiagnosis,
      (payload.symptoms as any)?.clinicalSummary,
      ...(payload.visionFindings || []).map((v) => v.condition)
    ]
      .filter(Boolean)
      .join(' ')
      .toLowerCase();

    const isOcular =
      upperAnatomical === 'EYE_OPHTHALMOLOGY' ||
      lowerAnatomical.includes('eye') ||
      lowerAnatomical.includes('ophthalm') ||
      contextText.includes('conjunctivit') ||
      contextText.includes('blepharit') ||
      contextText.includes('episclerit') ||
      contextText.includes('sclerit') ||
      contextText.includes('ophthalm');

    const isSkin =
      !isOcular &&
      (upperAnatomical === 'SKIN_EPIDERMIS' ||
        lowerAnatomical.includes('skin') ||
        lowerAnatomical.includes('epidermis') ||
        contextText.includes('dermatit') ||
        contextText.includes('eczema') ||
        contextText.includes('rash'));

    const vitals = payload.symptoms?.vitals || {};
    const riskScore = payload.multimodalRiskScore ?? 0.5;
    const coughCategory = payload.audioClassification?.predictedCategory;
    const visionFindings = payload.visionFindings || [];

    // Purely respiratory ICD-11 categories that must receive strict 0% probability when non-respiratory
    const PURELY_RESPIRATORY_CODES = new Set(['1B10.0', '1B10', 'CA00', 'CA01', 'CA0B', 'CA40']);

    // Calculate raw logit score for each ICD-11 candidate
    const candidateScores: Array<{
      concept: ICD11Concept;
      rawLogit: number;
      isMasked: boolean;
      matchedCriteria: string[];
      clinicalRationale: string;
    }> = [];

    const primaryDx = ((payload.symptoms as any)?.primaryDiagnosis || '').toLowerCase().trim();

    for (const concept of concepts) {
      let score = 0.0;
      let isMasked = false;
      const matched: string[] = [];
      const criteria = concept.clinicalCriteria;
      const conceptCode = concept.code.toUpperCase();
      const conceptTitleLower = concept.title.toLowerCase();

      // -------------------------------------------------------------
      // 1. Anatomical Hard-Gating (Gating Network prior to Softmax)
      // -------------------------------------------------------------
      if (isOcular) {
        if (PURELY_RESPIRATORY_CODES.has(conceptCode) || concept.category === 'Respiratory Diseases') {
          // Hard-zero out respiratory categories for ocular symptom presentations: logit = -Infinity
          isMasked = true;
          score = -Infinity;
        } else if (conceptCode === '9A60') {
          // Prioritize 9A60 Infectious Conjunctivitis
          score += 10.0;
          matched.push('Anatomical hard-gating priority: Ocular pathology (9A60 Infectious Conjunctivitis)');
        } else if (conceptCode === '9A03') {
          // Prioritize 9A03 Blepharitis
          score += 6.5;
          matched.push('Anatomical hard-gating priority: Ocular pathology (9A03 Blepharitis)');
        } else if (conceptCode === '9A20') {
          // Prioritize 9A20 Episcleritis / Scleritis
          score += 4.5;
          matched.push('Anatomical hard-gating priority: Ocular pathology (9A20 Episcleritis)');
        } else if (conceptCode === 'EK02') {
          // Prioritize EK02 Contact Dermatitis / Periorbital Erythema
          score += 5.5;
          matched.push('Anatomical hard-gating priority: Periorbital / Dermal pathology (EK02)');
        }
      } else if (isSkin) {
        if (PURELY_RESPIRATORY_CODES.has(conceptCode) || concept.category === 'Respiratory Diseases') {
          // Hard-zero out respiratory categories for purely dermatological presentations
          isMasked = true;
          score = -Infinity;
        } else if (conceptCode === 'FB80') {
          score += 8.0;
          matched.push('Anatomical hard-gating priority: Dermatological pathology (FB80)');
        } else if (conceptCode === 'EK02') {
          score += 6.0;
          matched.push('Anatomical hard-gating priority: Dermatological pathology (EK02)');
        }
      }

      if (!isMasked) {
        // Direct alignment with clinical assessment primary diagnosis
        if (primaryDx) {
          if (
            conceptTitleLower.includes(primaryDx) ||
            primaryDx.includes(conceptTitleLower) ||
            conceptCode.toLowerCase() === primaryDx ||
            (primaryDx.includes('conjunctivit') && conceptCode === '9A60') ||
            (primaryDx.includes('blepharit') && conceptCode === '9A03')
          ) {
            score += 12.0;
            matched.push(`Direct alignment with Clinical Assessment Primary Diagnosis: "${concept.title}"`);
          }
        }
        // 2. Keyword & Symptom overlap
        for (const kw of criteria.requiredKeywords) {
          const lowerKw = kw.toLowerCase();
          if (symptomsList.some((s) => s.includes(lowerKw) || lowerKw.includes(s))) {
            score += 2.5;
            matched.push(`Symptom match: "${kw}"`);
          }
        }

        // 3. Anatomical body location alignment
        if (criteria.anatomicalLocations && criteria.anatomicalLocations.length > 0) {
          if (criteria.anatomicalLocations.some((loc) => {
            const l = loc.toLowerCase();
            return l === lowerAnatomical || (isOcular && (l.includes('eye') || l.includes('ophthalm'))) || (isSkin && l.includes('skin'));
          })) {
            score += 2.0;
            matched.push(`Anatomical correlation: "${rawAnatomical}"`);
          }
        }

        // 4. Objective Vitals & rPPG threshold triggers
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

        // 5. Acoustic Cough pattern alignment
        if (criteria.coughCategories && coughCategory) {
          if (criteria.coughCategories.includes(coughCategory)) {
            score += 2.8;
            matched.push(`Acoustic classifier finding: "${coughCategory}"`);
          }
        }

        // 6. Computer Vision pattern alignment
        if (criteria.visionPatterns && visionFindings.length > 0) {
          for (const finding of visionFindings) {
            if (criteria.visionPatterns.some((vp) => finding.condition.toLowerCase().includes(vp.toLowerCase()))) {
              score += 3.0 * (finding.confidence || 0.8);
              matched.push(`Visual pathology finding: "${finding.condition}"`);
            }
          }
        }

        // 7. Multimodal Risk Tier compatibility
        if (criteria.minRiskScore !== undefined) {
          if (riskScore >= criteria.minRiskScore) {
            score += 1.5;
          } else {
            score -= 1.0;
          }
        }
      }

      // Construct explanatory rationale summary
      const clinicalRationale =
        matched.length > 0
          ? matched.slice(0, 3).join('; ')
          : isMasked
          ? 'Anatomically filtered category based on clinical presenting site'
          : 'Low baseline statistical prior across presenting clinical features';

      candidateScores.push({
        concept,
        rawLogit: score,
        isMasked,
        matchedCriteria: matched,
        clinicalRationale
      });
    }

    // Technical Guardrail 2: Softmax Normalization Safeguard with Logit Clipping [-20, 20]
    // and Temperature Scaling (T = 1.2 - 1.5)
    // Masked candidates (-Infinity) strictly receive probability 0.0000 (0%).
    const unmaskedScores = candidateScores.filter((c) => !c.isMasked && c.rawLogit !== -Infinity);
    const maxScaledLogit = unmaskedScores.length > 0
      ? Math.max(...unmaskedScores.map((c) => Math.max(-20.0, Math.min(20.0, c.rawLogit)) / safeTemperature))
      : 0.0;

    const expValues = candidateScores.map((c) => {
      if (c.isMasked || c.rawLogit === -Infinity) {
        return 0.0;
      }
      const clipped = Math.max(-20.0, Math.min(20.0, c.rawLogit));
      return Math.exp((clipped / safeTemperature) - maxScaledLogit);
    });

    const sumExp = expValues.reduce((sum, v) => sum + v, 0);

    const candidates: DifferentialDiagnosisCandidate[] = candidateScores.map((c, idx) => {
      let prob = 0.0;
      if (!c.isMasked && c.rawLogit !== -Infinity && sumExp > 0) {
        prob = expValues[idx] / sumExp;
      }
      return {
        code: c.concept.code,
        title: c.concept.title,
        category: c.concept.category,
        uri: c.concept.uri,
        probability: Math.round(prob * 10000) / 10000, // 4 decimal places
        logitScore: c.isMasked ? -99.0 : Math.round(c.rawLogit * 100) / 100,
        matchedCriteria: c.matchedCriteria,
        clinicalRationale: c.clinicalRationale
      };
    });

    // Sort descending by posterior probability: non-zero candidates first, then masked candidates
    candidates.sort((a, b) => b.probability - a.probability);

    // Return ranked candidates: return top candidates with positive probability,
    // plus any evaluated candidate for inspection (e.g. top 6 or all non-zero + masked)
    const nonZeroCount = candidates.filter((c) => c.probability > 0).length;
    return candidates.slice(0, Math.max(5, Math.min(8, nonZeroCount + 2)));
  }
}
