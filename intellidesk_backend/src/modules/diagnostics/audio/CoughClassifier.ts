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
  /**
   * Constructs the functional Cough Classification Model graph in TensorFlow.js.
   * Input: [null, 16] acoustic feature vector
   * Layers: Dense(64, relu) -> BatchNorm -> Dropout(0.25) -> Dense(32, relu) -> Dropout(0.15) -> Dense(16, relu) -> Dense(4, softmax)
   */
  /**
   * Constructs the functional Cough Classification Model graph in TensorFlow.js.
   * Input: [null, 16] acoustic feature vector
   * Layers: Dense(48, relu, L2) -> BatchNorm -> Dropout(0.25) -> Dense(24, relu, L2) -> Dropout(0.20) -> Dense(4, softmax, L2)
   */
  public static buildModel(): tf.LayersModel {
    const model = tf.sequential();

    model.add(tf.layers.dense({
      units: 48,
      activation: 'relu',
      kernelInitializer: 'heNormal',
      kernelRegularizer: tf.regularizers.l2({ l2: 1e-4 }),
      inputShape: [AUDIO_FEATURE_DIM],
      name: 'cough_dense_1'
    }));
    model.add(tf.layers.batchNormalization({ name: 'cough_bn_1' }));
    model.add(tf.layers.dropout({ rate: 0.25, name: 'cough_dropout_1' }));

    model.add(tf.layers.dense({
      units: 24,
      activation: 'relu',
      kernelInitializer: 'heNormal',
      kernelRegularizer: tf.regularizers.l2({ l2: 1e-4 }),
      name: 'cough_dense_2'
    }));
    model.add(tf.layers.dropout({ rate: 0.20, name: 'cough_dropout_2' }));

    model.add(tf.layers.dense({
      units: 4,
      activation: 'softmax',
      kernelInitializer: 'glorotNormal',
      kernelRegularizer: tf.regularizers.l2({ l2: 1e-4 }),
      name: 'cough_class_output'
    }));

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

    const saveUrl = `file://${COUGH_MODEL_DIR.replace(/\\/g, '/')}`;
    const loadUrl = fs.existsSync(COUGH_MODEL_JSON_PATH)
      ? `file://${COUGH_MODEL_JSON_PATH.replace(/\\/g, '/')}`
      : 'file://./models/cough_classifier/model.json';

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
   * Employs Temperature Scaling (T = 1.35) for probability calibration to prevent
   * uncalibrated overconfident softmax saturation.
   */
  public static async classify(
    features: number[] | Float32Array
  ): Promise<CoughClassificationResult> {
    const startTime = Date.now();
    const model = await this.loadOrBootstrapModel();

    // Validate feature dimensions & Z-score bounds [-4.0, +4.0]
    const featureArray = Array.from(features);
    const sanitizedFeatures = new Array<number>(AUDIO_FEATURE_DIM).fill(0.0);
    for (let i = 0; i < AUDIO_FEATURE_DIM; i++) {
      const val = Number(featureArray[i]);
      sanitizedFeatures[i] = Math.min(4.0, Math.max(-4.0, isNaN(val) ? 0.0 : val));
    }

    const inputVector = sanitizedFeatures;
    const isAllZeros = inputVector.every(v => v === 0);
    const hasNaN = inputVector.some(isNaN);

    console.log("Cough Input Tensor Stats:", {
      min: Number(Math.min(...inputVector).toFixed(4)),
      max: Number(Math.max(...inputVector).toFixed(4)),
      mean: Number((inputVector.reduce((a, b) => a + b, 0) / inputVector.length).toFixed(4)),
      hasNaN,
      isAllZeros
    });

    // Guardrail: reject dead zero or NaN tensors
    if (isAllZeros || hasNaN) {
      throw new Error("Invalid Audio Stream: Zero/NaN buffer received from DSP");
    }

    return tf.tidy(() => {
      const inputTensor = tf.tensor2d([sanitizedFeatures], [1, AUDIO_FEATURE_DIM]);
      const predTensor = model.predict(inputTensor) as tf.Tensor;
      const rawProbs = predTensor.dataSync();

      // Temperature scaling calibration (Guo et al. ICML 2017) to prevent overconfident softmax saturation
      const temperature = 1.30;
      const logit0 = Math.log(Math.max(1e-7, rawProbs[0])) / temperature;
      const logit1 = Math.log(Math.max(1e-7, rawProbs[1])) / temperature;
      const logit2 = Math.log(Math.max(1e-7, rawProbs[2])) / temperature;
      const logit3 = Math.log(Math.max(1e-7, rawProbs[3])) / temperature;

      const maxLogit = Math.max(logit0, logit1, logit2, logit3);
      const e0 = Math.exp(logit0 - maxLogit);
      const e1 = Math.exp(logit1 - maxLogit);
      const e2 = Math.exp(logit2 - maxLogit);
      const e3 = Math.exp(logit3 - maxLogit);
      const sumE = e0 + e1 + e2 + e3;

      const normalProb = Number((e0 / sumE).toFixed(4));
      const dryProb = Number((e1 / sumE).toFixed(4));
      const wetProb = Number((e2 / sumE).toFixed(4));
      const wheezeProb = Number((e3 / sumE).toFixed(4));

      const probs = [normalProb, dryProb, wetProb, wheezeProb];
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

      const res = {
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

      console.log(`🩺 [CoughClassifier] Prediction: "${predictedCategory}" (${(confidence * 100).toFixed(1)}%) | Normal: ${(normalProb * 100).toFixed(1)}% | Dry: ${(dryProb * 100).toFixed(1)}% | Wet: ${(wetProb * 100).toFixed(1)}% | Wheeze: ${(wheezeProb * 100).toFixed(1)}% | RedFlag: ${isRedFlag}`);
      if (isRedFlag && redFlagReason) {
        console.warn(`🚨 [CoughClassifier] ${redFlagReason}`);
      }

      return res;
    });
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
