export type CoughCategory =
  | 'Normal Respiratory'
  | 'Dry/Irritative Cough'
  | 'Wet/Productive Cough'
  | 'Wheeze/Stridor';

export const COUGH_CATEGORIES: CoughCategory[] = [
  'Normal Respiratory',
  'Dry/Irritative Cough',
  'Wet/Productive Cough',
  'Wheeze/Stridor'
];

export const TARGET_SAMPLE_RATE = 16000;
export const AUDIO_FEATURE_DIM = 16;
export const MFCC_COUNT = 12;
export const FRAME_SIZE = 512;
export const HOP_SIZE = 256;
export const WHEEZE_RED_FLAG_CONFIDENCE_THRESHOLD = 0.70;
export const RESPIRATORY_RED_FLAG_FLOOR = 0.75;

export interface SpectralMetrics {
  centroid: number; // Normalized [0.0, 1.0]
  rolloff: number;  // Normalized [0.0, 1.0]
  flux: number;     // Normalized [0.0, 1.0]
  zcr: number;      // Normalized [0.0, 1.0]
}

export interface AudioFeatureExtractionResult {
  featureVector: number[]; // 16-d strictly scaled to [0.0, 1.0]
  originalSampleRate: number;
  resampledRate: number; // 16000 Hz
  durationSeconds: number;
  pcmSampleCount: number;
  isResampled: boolean;
  spectralMetrics: SpectralMetrics;
  mfccCoefficients: number[]; // 12-d normalized
}

export interface CoughClassificationResult {
  predictedCategory: CoughCategory;
  confidence: number; // [0.0, 1.0]
  probabilities: {
    normalRespiratory: number;
    dryIrritativeCough: number;
    wetProductiveCough: number;
    wheezeStridor: number;
  };
  isRedFlagRespiratory: boolean;
  redFlagReason?: string;
  featureVector: number[]; // 16-d
  latencyMs?: number;
}
