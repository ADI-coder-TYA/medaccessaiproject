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

// Acoustic feature baseline statistics for Z-score standardization (12 MFCCs + Centroid, Rolloff, Flux, ZCR)
export const ACOUSTIC_MEANS: number[] = [
  20.0, 10.0, 2.0, -4.0, -8.0, -11.0, -12.0, -10.0, -8.0, -5.0, -2.0, 0.0,
  0.20, 0.30, 0.045, 0.080
];

export const ACOUSTIC_STDS: number[] = [
  15.0, 12.0, 10.0, 8.0, 8.0, 7.0, 7.0, 7.0, 6.0, 6.0, 5.0, 5.0,
  0.12, 0.16, 0.035, 0.060
];

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
