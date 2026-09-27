import {
  SymptomInputPayload,
  MultimodalRiskResult
} from './types.js';
import { VisionEmbeddingResult } from '../vision/types.js';
import { assessMultimodalRisk } from './assessMultimodalRisk.js';
import { MultimodalFusionModel } from './MultimodalFusionModel.js';

export class MultimodalRiskNetwork {
  private static isModelLoaded = false;
  private static readonly MC_DROPOUT_RUNS = 10;

  public static async initialize(): Promise<void> {
    if (this.isModelLoaded) return;
    await MultimodalFusionModel.loadOrBootstrapModel();
    this.isModelLoaded = true;
    console.log('🧬 [Diagnostics Fusion] Multimodal Risk Fusion Neural Network initialized');
  }

  /**
   * Fuses vision embedding vector (128-d), structured symptoms, vitals, and audio biomarkers into a unified clinical risk assessment.
   * Leverages TensorFlow.js Monte Carlo Dropout deep neural inference and Hugging Face disease prediction.
   */
  public static async assessRisk(
    symptoms: SymptomInputPayload,
    visionResult?: VisionEmbeddingResult,
    audioOptions?: { audioBuffer?: Buffer; audioFeatures?: number[] }
  ): Promise<MultimodalRiskResult> {
    await this.initialize();

    return assessMultimodalRisk({
      visualEmbeddings: visionResult?.featureVector || null,
      visionFindings: visionResult?.topFindings,
      symptomData: symptoms,
      patientVitals: symptoms.vitals,
      audioBuffer: audioOptions?.audioBuffer,
      audioFeatures: audioOptions?.audioFeatures,
      mcSamples: this.MC_DROPOUT_RUNS
    });
  }
}
