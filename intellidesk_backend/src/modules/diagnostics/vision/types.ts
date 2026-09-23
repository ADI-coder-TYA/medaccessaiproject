/**
 * Types and interfaces for Clinical Diagnostic Computer Vision Pipeline
 */

export type ClinicalImageCategory = 
  | 'DERMATOLOGY_RASH'
  | 'SKIN_LESION'
  | 'WOUND_HEALING'
  | 'CONJUNCTIVITIS_EYE'
  | 'ORAL_THROAT_INFECTION'
  | 'GENERAL_PHYSICAL_SYMPTOM';

export interface ClinicalImageInput {
  imageBuffer?: Buffer;
  imageUrl?: string;
  mimeType?: string;
  categoryHint?: ClinicalImageCategory;
}

export interface ClinicalImageFinding {
  label: string;
  confidence: number;
  clinicalSignificance: 'BENIGN' | 'LOW_RISK' | 'MODERATE_SUSPICION' | 'HIGH_ALERT';
  description: string;
}

export interface VisionEmbeddingResult {
  embeddingDimension: number; // e.g. 128 or 512
  featureVector: number[]; // 128-d or 512-d normalized visual embeddings
  primaryCategory: ClinicalImageCategory;
  predictedCondition: string;
  topFindings: ClinicalImageFinding[];
  visualQualityScore: number; // 0.0 - 1.0 (lighting, focus, clarity)
  featureMapDimensions?: [number, number, number]; // [H, W, C] for Grad-CAM
}
