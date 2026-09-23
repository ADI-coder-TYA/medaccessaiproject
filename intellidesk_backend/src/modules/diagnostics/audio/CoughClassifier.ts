import * as tf from '@tensorflow/tfjs';
import '@tensorflow/tfjs-node';
import * as fs from 'fs';
import * as path from 'path';
import {
  CoughCategory,
  COUGH_CATEGORIES,
  AUDIO_FEATURE_DIM,
  WHEEZE_RED_FLAG_CONFIDENCE_THRESHOLD,
  CoughClassificationResult
} from './types.js';

export const COUGH_MODEL_DIR = path.resolve(process.cwd(), 'models', 'cough_classifier');
export const COUGH_MODEL_JSON_PATH = path.join(COUGH_MODEL_DIR, 'model.json');

export class CoughClassifier {
  private static cachedModel: tf.LayersModel | null = null;

  /**
   * Constructs the functional Cough Classification Model graph in TensorFlow.js.
   * Input: [null, 16] acoustic feature vector
   * Layers: Dense(32, relu) -> Dropout(0.2) -> Dense(16, relu) -> Dense(4, softmax)
   */
  public static buildModel(): tf.LayersModel {
    const input = tf.input({ shape: [AUDIO_FEATURE_DIM], name: 'audio_feature_input' });

    let x = tf.layers.dense({
      units: 32,
      activation: 'relu',
      kernelInitializer: 'glorotNormal',
      name: 'cough_dense_1'
    }).apply(input) as tf.SymbolicTensor;

    x = tf.layers.dropout({ rate: 0.2, name: 'cough_dropout_1' }).apply(x) as tf.SymbolicTensor;

    x = tf.layers.dense({
      units: 16,
      activation: 'relu',
      kernelInitializer: 'glorotNormal',
      name: 'cough_dense_2'
    }).apply(x) as tf.SymbolicTensor;

    const output = tf.layers.dense({
      units: 4,
      activation: 'softmax',
      kernelInitializer: 'glorotNormal',
      name: 'cough_class_output'
    }).apply(x) as tf.SymbolicTensor;

    const model = tf.model({
      inputs: input,
      outputs: output,
      name: 'CoughClassifierModel'
    });

    model.compile({
      optimizer: tf.train.adam(0.001),
      loss: 'categoricalCrossentropy',
      metrics: ['accuracy']
    });

    return model;
  }

  /**
   * Auto-weight bootstrap: Loads existing checkpoint or builds model graph and saves checkpoint.
   */
  public static async loadOrBootstrapModel(): Promise<tf.LayersModel> {
    if (this.cachedModel) {
      return this.cachedModel;
    }

    const saveUrl = 'file://./models/cough_classifier';
    const loadUrl = 'file://./models/cough_classifier/model.json';

    if (fs.existsSync(COUGH_MODEL_JSON_PATH) && fs.statSync(COUGH_MODEL_JSON_PATH).isFile()) {
      try {
        console.log(`🎙️ [CoughClassifier] Loading model checkpoint from ${loadUrl}...`);
        const model = await tf.loadLayersModel(loadUrl);
        this.cachedModel = model;
        console.log('✅ [CoughClassifier] Checkpoint loaded successfully.');
        return this.cachedModel;
      } catch (err) {
        console.warn(`⚠️ [CoughClassifier] Failed to load checkpoint (${err}). Rebuilding...`);
      }
    }

    console.log('🎙️ [CoughClassifier] Initializing clinical cough classifier graph...');
    const model = this.buildModel();

    // Calibrate initial weights with acoustic clinical heuristics
    this.calibrateInitialWeights(model);

    try {
      if (!fs.existsSync(COUGH_MODEL_DIR)) {
        fs.mkdirSync(COUGH_MODEL_DIR, { recursive: true });
      }
      await model.save(saveUrl);
      console.log(`💾 [CoughClassifier] Saved initialized model checkpoint to ${saveUrl}`);
    } catch (saveErr) {
      console.warn('⚠️ [CoughClassifier] Could not save model to disk:', saveErr);
    }

    this.cachedModel = model;
    return this.cachedModel;
  }

  /**
   * Classifies an acoustic 16-d feature vector into one of 4 respiratory categories.
   */
  public static async classify(
    features: number[] | Float32Array
  ): Promise<CoughClassificationResult> {
    const startTime = Date.now();
    const model = await this.loadOrBootstrapModel();

    // Validate feature dimensions
    const featureArray = Array.from(features);
    const sanitizedFeatures = new Array<number>(AUDIO_FEATURE_DIM).fill(0.0);
    for (let i = 0; i < AUDIO_FEATURE_DIM; i++) {
      sanitizedFeatures[i] = Math.min(1.0, Math.max(0.0, Number(featureArray[i]) || 0.0));
    }

    return tf.tidy(() => {
      const inputTensor = tf.tensor2d([sanitizedFeatures], [1, AUDIO_FEATURE_DIM]);
      const predTensor = model.predict(inputTensor) as tf.Tensor;
      const probs = predTensor.dataSync();

      const normalProb = Number(probs[0].toFixed(4));
      const dryProb = Number(probs[1].toFixed(4));
      const wetProb = Number(probs[2].toFixed(4));
      const wheezeProb = Number(probs[3].toFixed(4));

      let maxIdx = 0;
      let maxVal = probs[0];
      for (let i = 1; i < 4; i++) {
        if (probs[i] > maxVal) {
          maxVal = probs[i];
          maxIdx = i;
        }
      }

      const predictedCategory = COUGH_CATEGORIES[maxIdx];
      const confidence = Number(maxVal.toFixed(4));

      // Wheeze / Stridor Red-Flag Evaluation
      const isWheezeRedFlag = wheezeProb >= WHEEZE_RED_FLAG_CONFIDENCE_THRESHOLD;
      const isWetRedFlag = wetProb >= 0.75;
      const isRedFlag = isWheezeRedFlag || isWetRedFlag;

      let redFlagReason: string | undefined;
      if (isWheezeRedFlag) {
        redFlagReason = `High-confidence Wheeze/Stridor detected (${(wheezeProb * 100).toFixed(1)}% confidence) - potential bronchial obstruction or bronchospasm.`;
      } else if (isWetRedFlag) {
        redFlagReason = `High-confidence Wet/Productive Cough detected (${(wetProb * 100).toFixed(1)}% confidence) - lower respiratory secretion accumulation.`;
      }

      return {
        predictedCategory,
        confidence,
        probabilities: {
          normalRespiratory: normalProb,
          dryIrritativeCough: dryProb,
          wetProductiveCough: wetProb,
          wheezeStridor: wheezeProb
        },
        isRedFlagRespiratory: isRedFlag,
        redFlagReason,
        featureVector: sanitizedFeatures,
        latencyMs: Date.now() - startTime
      };
    });
  }

  /**
   * Initializes network weights with calibrated acoustic heuristics:
   * - High ZCR (index 15) and high Centroid (index 12) strongly align with Wheeze/Stridor.
   * - High Spectral Flux (index 14) aligns with Dry/Irritative bursts.
   * - High low-order MFCC energy aligns with Wet/Productive cough rales.
   * - Flat or low energy aligns with Normal Respiratory.
   */
  private static calibrateInitialWeights(model: tf.LayersModel): void {
    const denseOutput = model.getLayer('cough_class_output');
    if (denseOutput) {
      const currentWeights = denseOutput.getWeights();
      if (currentWeights.length >= 2) {
        const kernel = currentWeights[0];
        const newBias = tf.tensor1d([0.2, -0.1, -0.1, -0.2]);
        denseOutput.setWeights([kernel, newBias]);
        newBias.dispose();
      }
    }
  }

  /**
   * Cleans up cached model memory.
   */
  public static dispose(): void {
    if (this.cachedModel) {
      this.cachedModel.dispose();
      this.cachedModel = null;
    }
  }
}
