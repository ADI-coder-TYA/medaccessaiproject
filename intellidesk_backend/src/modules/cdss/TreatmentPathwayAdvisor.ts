import {
  DifferentialDiagnosisCandidate,
  TreatmentPathway
} from './types.js';
import { ICD11ConceptStore } from './ICD11ConceptStore.js';

export class TreatmentPathwayAdvisor {
  /**
   * Recommends evidence-based diagnostic labs, imaging, pharmacological therapy,
   * and clinical follow-up intervals based on the primary differential diagnosis candidate.
   */
  public static recommendPathway(
    primaryCandidate: DifferentialDiagnosisCandidate,
    riskScore = 0.5,
    isOverridden = false
  ): TreatmentPathway {
    const concept = ICD11ConceptStore.getConceptByCode(primaryCandidate.code);

    let urgencyLevel: 'ROUTINE' | 'PROMPT_EVALUATION' | 'IMMEDIATE_EMERGENCY' = 'ROUTINE';
    if (riskScore >= 0.75 || primaryCandidate.code === 'CA40' || primaryCandidate.code === 'BA00') {
      urgencyLevel = 'IMMEDIATE_EMERGENCY';
    } else if (riskScore >= 0.40 || primaryCandidate.code === 'CA00') {
      urgencyLevel = 'PROMPT_EVALUATION';
    }

    if (concept) {
      return {
        primaryCode: concept.code,
        primaryTitle: concept.title,
        recommendedRx: concept.firstLinePathway.recommendedRx,
        labOrders: concept.firstLinePathway.labOrders,
        imagingOrders: concept.firstLinePathway.imagingOrders,
        monitoringFrequency: concept.firstLinePathway.monitoringFrequency,
        followUpDays: concept.firstLinePathway.followUpDays,
        urgentRedFlags: concept.firstLinePathway.urgentRedFlags,
        urgencyLevel
      };
    }

    // Fallback generalized pathway for non-standard or manually keyed ICD codes
    return {
      primaryCode: primaryCandidate.code,
      primaryTitle: primaryCandidate.title || 'Unspecified Clinical Presentation',
      recommendedRx: [
        {
          genericName: 'Symptomatic Supportive Care',
          dosage: 'Per Physician Discretion',
          frequency: 'PRN',
          duration: '3 - 5 days',
          clinicalNotes: 'Tailor pharmacological treatment following attending physician examination.'
        }
      ],
      labOrders: ['Complete Blood Count (CBC)', 'Basic Metabolic Panel (BMP)'],
      imagingOrders: ['Diagnostic plain radiography guided by physical exam findings'],
      monitoringFrequency: 'Daily symptom log & vital signs monitoring',
      followUpDays: urgencyLevel === 'IMMEDIATE_EMERGENCY' ? 1 : 5,
      urgentRedFlags: [
        'Hemodynamic instability (HR > 120 or SBP < 90)',
        'SpO2 < 92% on ambient air',
        'Acute altered mental status or neurological deficit'
      ],
      urgencyLevel
    };
  }
}
