import { SymptomInputPayload, MultimodalRiskResult } from '../fusion/types.js';
import { VisionEmbeddingResult } from '../vision/types.js';

export interface FeatureAttribution {
  featureName: string;
  category: 'SYMPTOMS' | 'VITALS' | 'VISION' | 'DEMOGRAPHICS';
  contributionWeight: number; // e.g. +0.32 (increases risk) or -0.15 (decreases risk)
  percentageImpact: number; // 0 - 100%
  description: string;
}

export interface TriFeatureBreakdown {
  visualAnalysisPercent: number; // e.g. 60
  symptomsPercent: number; // e.g. 30
  agePercent: number; // e.g. 10
  formattedBreakdown: string; // "Visual Analysis: 60%, Symptoms: 30%, Age: 10%"
}

export interface ShapExplanationResult {
  baseValue: number; // Baseline population prior (0.15)
  finalRiskScore: number;
  featureContributionBreakdown: TriFeatureBreakdown;
  attributions: FeatureAttribution[];
  summaryNarrative: string;
}

export class FeatureImportanceEngine {
  /**
   * Calculates the primary tri-feature relative contribution breakdown:
   * [Visual Analysis, Symptoms / Pain Scale, Age / Demographics].
   * Strictly normalizes to 100% and produces the required display string:
   * e.g. "Visual Analysis: 60%, Symptoms: 30%, Age: 10%"
   */
  public static calculateTriFeatureBreakdown(
    symptoms: SymptomInputPayload,
    riskResult: MultimodalRiskResult,
    vision?: VisionEmbeddingResult | null
  ): TriFeatureBreakdown {
    // 1. Raw Visual Contribution
    let rawVisual = 0.0;
    if (vision && vision.topFindings && vision.topFindings.length > 0) {
      const topFinding = vision.topFindings[0];
      const severityMultiplier =
        topFinding.clinicalSignificance === 'HIGH_ALERT' ? 1.0 :
        topFinding.clinicalSignificance === 'MODERATE_SUSPICION' ? 0.8 : 0.5;
      rawVisual = 0.45 + (topFinding.confidence * 0.25 * severityMultiplier);
    }

    // 2. Raw Symptoms / Pain Scale Contribution
    const painWeight = (Math.max(1, symptoms.painScale) / 10.0) * 0.45;
    const durationWeight = Math.min(0.20, (symptoms.durationDays || 1) / 30.0 * 0.20);
    const redFlagCount = (symptoms.symptoms || []).filter(s => {
      const lower = s.toLowerCase();
      return lower.includes('chest') || lower.includes('breath') || lower.includes('fever') || lower.includes('blood');
    }).length;
    const redFlagWeight = redFlagCount * 0.10;
    const rawSymptoms = Math.max(0.15, painWeight + durationWeight + redFlagWeight);

    // 3. Raw Age / Demographics Contribution
    const age = symptoms.demographics?.age ?? 35;
    const ageWeight = (age / 100.0) * 0.15;
    const conditionsWeight = (symptoms.demographics?.preExistingConditions?.length || 0) * 0.05;
    const rawAge = Math.max(0.05, ageWeight + conditionsWeight);

    // Normalize so sum of percentages equals exactly 100%
    const totalRaw = rawVisual + rawSymptoms + rawAge;
    let visualPercent = Math.round((rawVisual / totalRaw) * 100);
    let symptomsPercent = Math.round((rawSymptoms / totalRaw) * 100);
    let agePercent = 100 - (visualPercent + symptomsPercent); // Guarantee exact sum = 100

    if (agePercent < 0) {
      symptomsPercent += agePercent;
      agePercent = 0;
    }

    const formattedBreakdown = `Visual Analysis: ${visualPercent}%, Symptoms: ${symptomsPercent}%, Age: ${agePercent}%`;

    return {
      visualAnalysisPercent: visualPercent,
      symptomsPercent,
      agePercent,
      formattedBreakdown
    };
  }

  /**
   * Computes comprehensive SHAP-inspired feature attributions and the tri-feature breakdown.
   */
  public static calculateShapValues(
    symptoms: SymptomInputPayload,
    riskResult: MultimodalRiskResult,
    vision?: VisionEmbeddingResult | null
  ): ShapExplanationResult {
    const baseValue = 0.15; // Baseline prior
    const attributions: FeatureAttribution[] = [];

    // Tri-feature relative breakdown
    const featureContributionBreakdown = this.calculateTriFeatureBreakdown(symptoms, riskResult, vision);

    // 1. Pain Scale Attribution
    if (symptoms.painScale > 0) {
      const painImpact = Number(((symptoms.painScale / 10) * 0.25).toFixed(3));
      attributions.push({
        featureName: `Pain Level (${symptoms.painScale}/10)`,
        category: 'SYMPTOMS',
        contributionWeight: painImpact,
        percentageImpact: 0,
        description: symptoms.painScale >= 7 ? 'Severe pain significantly elevated acute risk calculation.' : 'Mild to moderate pain reported.'
      });
    }

    // 2. Symptom Duration Attribution
    if (symptoms.durationDays > 0) {
      const durImpact = symptoms.durationDays > 7 ? 0.12 : 0.04;
      attributions.push({
        featureName: `Duration (${symptoms.durationDays} days)`,
        category: 'SYMPTOMS',
        contributionWeight: durImpact,
        percentageImpact: 0,
        description: symptoms.durationDays > 7 ? 'Prolonged symptom course indicates non-transient pathology.' : 'Acute duration.'
      });
    }

    // 3. Clinical Vision Findings Attribution
    if (vision && vision.topFindings && vision.topFindings.length > 0) {
      const top = vision.topFindings[0];
      const visionImpact = Number((top.confidence * (top.clinicalSignificance === 'MODERATE_SUSPICION' || top.clinicalSignificance === 'HIGH_ALERT' ? 0.35 : 0.10)).toFixed(3));
      attributions.push({
        featureName: `Visual finding: ${top.label}`,
        category: 'VISION',
        contributionWeight: visionImpact,
        percentageImpact: 0,
        description: `Visual classifier identified ${top.label} with ${(top.confidence * 100).toFixed(0)}% confidence.`
      });
    }

    // 4. Vitals Sign Attributions
    if (symptoms.vitals) {
      if (symptoms.vitals.temperatureCelsius && symptoms.vitals.temperatureCelsius >= 38.0) {
        attributions.push({
          featureName: `Elevated Temperature (${symptoms.vitals.temperatureCelsius}°C)`,
          category: 'VITALS',
          contributionWeight: 0.18,
          percentageImpact: 0,
          description: 'Febrile state indicates systemic inflammatory or infectious response.'
        });
      }

      if (symptoms.vitals.heartRate && symptoms.vitals.heartRate > 100) {
        attributions.push({
          featureName: `Tachycardia (${symptoms.vitals.heartRate} bpm)`,
          category: 'VITALS',
          contributionWeight: 0.14,
          percentageImpact: 0,
          description: 'Elevated resting heart rate increases acute triage weighting.'
        });
      }

      if (symptoms.vitals.oxygenSaturation && symptoms.vitals.oxygenSaturation < 95) {
        attributions.push({
          featureName: `Low SpO2 (${symptoms.vitals.oxygenSaturation}%)`,
          category: 'VITALS',
          contributionWeight: 0.28,
          percentageImpact: 0,
          description: 'Sub-optimal blood oxygen saturation flags acute respiratory priority.'
        });
      }
    }

    // 5. Patient Age Attribution
    const age = symptoms.demographics?.age;
    if (age != null) {
      const ageImpact = age > 65 ? 0.15 : age < 5 ? 0.10 : 0.03;
      attributions.push({
        featureName: `Patient Age (${age} years)`,
        category: 'DEMOGRAPHICS',
        contributionWeight: ageImpact,
        percentageImpact: 0,
        description: age > 65 ? 'Elevated demographic age risk factor.' : 'Nominal adult age bracket.'
      });
    }

    // 6. Individual Symptom Tokens
    for (const sym of (symptoms.symptoms || []).slice(0, 3)) {
      attributions.push({
        featureName: sym,
        category: 'SYMPTOMS',
        contributionWeight: 0.08,
        percentageImpact: 0,
        description: `Clinical symptom report of '${sym}'.`
      });
    }

    // Compute relative percentage impacts across individual attributions
    const totalPositive = attributions.reduce((acc, a) => acc + Math.max(0, a.contributionWeight), 0) || 1.0;
    for (const a of attributions) {
      a.percentageImpact = Math.round((Math.max(0, a.contributionWeight) / totalPositive) * 100);
    }

    // Sort by largest contribution
    attributions.sort((a, b) => b.contributionWeight - a.contributionWeight);

    const primaryDriver = attributions[0]?.featureName || 'Reported somatic symptoms';
    const summaryNarrative = `Primary risk driver is ${primaryDriver} (${attributions[0]?.percentageImpact || 0}% impact). Overall feature allocation: ${featureContributionBreakdown.formattedBreakdown}.`;

    return {
      baseValue,
      finalRiskScore: riskResult.riskScore,
      featureContributionBreakdown,
      attributions,
      summaryNarrative
    };
  }
}
