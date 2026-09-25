/**
 * Types and interfaces for Multimodal Diagnostic Fusion Engine
 */

export interface SymptomInputPayload {
  bodyLocation: string; // e.g. "Left Arm", "Throat", "Lower Abdomen"
  durationDays: number;
  painScale: number; // 1 - 10
  symptoms: string[];
  vitals?: {
    heartRate?: number;
    temperatureCelsius?: number;
    systolicBP?: number;
    diastolicBP?: number;
    respiratoryRate?: number;
    respirationRate?: number;
    oxygenSaturation?: number;
    hrvRmssdMs?: number;
    source?: string;
    rppgResult?: any;
    [key: string]: any;
  };
  demographics?: {
    age?: number;
    gender?: string;
    preExistingConditions?: string[];
  };
  additionalNotes?: string;
  patient_name?: string;
  patientName?: string;
}

export interface UncertaintyBounds {
  confidence: number; // e.g. 0.88 (88%)
  ciLower: number; // Lower bound (e.g. 0.84)
  ciUpper: number; // Upper bound (e.g. 0.92)
  epistemicVariance: number; // Monte Carlo dropout variance
  monteCarloSamples: number;
}

export type ClinicalRiskLevel = 'LOW' | 'MODERATE' | 'HIGH' | 'CRITICAL';

export const CLINICAL_RISK_TIERS = [
  'Low Risk',
  'Moderate Need',
  'Critical Referral'
] as const;

export type ClinicalRiskTier = typeof CLINICAL_RISK_TIERS[number];

export interface DifferentialDiagnosis {
  condition: string;
  probability: number;
  urgency: 'ROUTINE' | 'PROMPT_CARE' | 'EMERGENCY';
}

export interface MultimodalRiskResult {
  riskScore: number; // Normalized continuous score [0.0, 1.0]
  riskLevel: ClinicalRiskLevel;
  riskTier?: ClinicalRiskTier;
  tierProbabilities?: {
    lowRisk: number;
    moderateNeed: number;
    criticalReferral: number;
  };
  uncertaintyBounds: UncertaintyBounds;
  primaryDiagnosis: string;
  differentialDiagnoses: DifferentialDiagnosis[];
  clinicalRecommendations: string[];
  featureWeights: {
    visualContribution: number;
    symptomContribution: number;
    vitalsContribution: number;
    demographicContribution: number;
    audioContribution?: number;
  };
  requiresImmediatePhysicianReview: boolean;
  safetyNet?: {
    triggered: boolean;
    reasons: string[];
    enforcedFloor: number | null;
  };
}

