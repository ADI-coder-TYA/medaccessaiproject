/**
 * Types and interfaces for Clinical Decision Support System (CDSS) Module
 */

export const WHO_ICD11_URI_STEM = 'http://id.who.int/icd/release/11/mms';

export const MANDATORY_CDSS_DISCLAIMER =
  'AI Clinical Decision Support Tool — For Licensed Practitioner Reference Only. Requires Attending Physician Validation.';

export interface ICD11ClinicalCriteria {
  requiredKeywords: string[];
  anatomicalLocations?: string[];
  vitalsTriggers?: {
    feverMinCelsius?: number;
    tachycardiaMinBpm?: number;
    bradycardiaMaxBpm?: number;
    hypoxiaMaxSpo2?: number;
    tachypneaMinBreathsPerMin?: number;
    hypertensionMinSystolic?: number;
  };
  coughCategories?: string[];
  visionPatterns?: string[];
  minRiskScore?: number;
}

export interface RecommendedMedication {
  brandName?: string;
  genericName: string;
  dosage: string;
  frequency: string;
  duration: string;
  clinicalNotes: string;
}

export interface FirstLinePathway {
  recommendedRx: RecommendedMedication[];
  labOrders: string[];
  imagingOrders: string[];
  monitoringFrequency: string;
  followUpDays: number;
  urgentRedFlags: string[];
}

export interface ICD11Concept {
  code: string;
  title: string;
  category: string;
  uri: string; // http://id.who.int/icd/release/11/mms/{code}
  clinicalCriteria: ICD11ClinicalCriteria;
  firstLinePathway: FirstLinePathway;
}

export interface DifferentialDiagnosisCandidate {
  code: string;
  title: string;
  category: string;
  uri: string;
  probability: number; // Normalized posterior probability in [0, 1]
  logitScore: number;
  matchedCriteria: string[];
  clinicalRationale: string;
}

export interface TreatmentPathway {
  primaryCode: string;
  primaryTitle: string;
  recommendedRx: RecommendedMedication[];
  labOrders: string[];
  imagingOrders: string[];
  monitoringFrequency: string;
  followUpDays: number;
  urgentRedFlags: string[];
  urgencyLevel: 'ROUTINE' | 'PROMPT_EVALUATION' | 'IMMEDIATE_EMERGENCY';
}

export interface ClinicianApproval {
  clinicianId: string;
  clinicianName: string;
  approvedAt: string;
  isOverridden: boolean;
  originalCode: string;
  overriddenCode?: string;
  overrideNotes?: string;
  signatureHash: string;
}

export interface CDSSEvaluationResult {
  id: string;
  screeningId?: string | null;
  patientId: string;
  institutionId?: string;
  institutionName?: string;
  primaryICD11Code: string;
  primaryICD11Title: string;
  primaryICD11Uri: string;
  differentialDiagnoses: DifferentialDiagnosisCandidate[];
  treatmentPathway: TreatmentPathway;
  temperatureScaling: number;
  regulatoryDisclaimer: string;
  modelUsed?: string;
  attendingClinicianApproval?: ClinicianApproval | null;
  createdAt: string;
  updatedAt: string;
}

export interface CDSSInputPayload {
  screeningId?: string | null;
  patientId: string;
  institutionId?: string;
  institutionName?: string;
  multimodalRiskScore: number;
  symptoms?: {
    symptoms?: string[];
    bodyLocation?: string;
    painScale?: number;
    durationDays?: number;
    vitals?: {
      temperatureCelsius?: number;
      heartRate?: number;
      systolicBP?: number;
      diastolicBP?: number;
      oxygenSaturation?: number;
      respirationRate?: number;
      rppgResult?: any;
    };
    clinicalNotes?: string;
    clinical_notes?: string;
    additionalNotes?: string;
    notes?: string;
    [key: string]: any;
  };
  clinicalNotes?: string;
  clinical_notes?: string;
  additionalNotes?: string;
  visionFindings?: Array<{ condition: string; confidence: number }>;
  audioClassification?: {
    predictedCategory: string;
    confidence: number;
    semanticAcousticProfile?: string;
  };
  acousticProfile?: string; // High-level semantic profile extracted via Meyda DSP
  audioFeatures?: number[]; // Raw 16-D feature vector
  temperature?: number; // Defaults to 1.25
  useCloudModel?: boolean; // When true or default with HF_TOKEN, uses Qwen/Qwen2.5-72B-Instruct
}
