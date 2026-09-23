export type DDISeverity = 'CONTRAINDICATED_SEVERE' | 'MODERATE_MONITOR' | 'MINOR' | 'SAFE';

export type AllergenGroup = 'PENICILLINS' | 'NSAIDS' | 'SULFA' | 'OPIOIDS' | 'MACROLIDES' | 'CEPHALOSPORINS' | 'STATINS' | 'TETRACYCLINES';

export interface ExtractedMedication {
  brandName: string;
  activeIngredient: string;
  dosage: string;
  frequency: string;
  duration?: string;
  rawText: string;
  confidence: number;
  matchedRxNormTerm?: string;
  allergenGroup?: AllergenGroup;
}

export interface DDIPairResult {
  drugA: string;
  drugB: string;
  severity: DDISeverity;
  clinicalMechanism: string;
  mitigationAdvice: string;
}

export interface AllergyConflictResult {
  allergenGroup: string;
  matchedDrug: string;
  activeIngredient: string;
  patientReaction?: string;
  severity: 'HIGH_RISK_ALLERGY' | 'CROSS_REACTIVITY_WARNING';
  alertMessage: string;
}

export interface RxScanSummary {
  id?: string;
  patientId?: string;
  imageUrl?: string;
  extractedDrugs: ExtractedMedication[];
  ddiWarnings: DDIPairResult[];
  allergyConflicts: AllergyConflictResult[];
  hasSafetyConflict: boolean;
  requiresPharmacistReview: boolean;
  rawOcrText?: string;
  createdAt?: string;
}

export interface PatientAllergy {
  id?: string;
  patientId: string;
  allergenGroup: string;
  reactionDescription?: string;
  createdAt?: string;
}

export interface PatientMedication {
  id?: string;
  patientId: string;
  medicationName: string;
  activeIngredient: string;
  dosage?: string;
  isActive: boolean;
  createdAt?: string;
}

export interface RxNormConcept {
  activeIngredient: string;
  brandAliases: string[];
  allergenGroup?: AllergenGroup;
  category: string;
}
