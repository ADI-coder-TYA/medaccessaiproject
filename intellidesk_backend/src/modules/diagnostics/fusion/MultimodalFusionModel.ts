import * as tf from '@tensorflow/tfjs';
import '@tensorflow/tfjs-node';
import * as fs from 'fs';
import * as path from 'path';
import { CLINICAL_RISK_TIERS, ClinicalRiskTier, UncertaintyBounds } from './types.js';
import { TOTAL_CONCATENATED_DIM } from './vectorAssembler.js';

export const FUSION_INPUT_DIM = TOTAL_CONCATENATED_DIM; // 168
export const FUSION_MODEL_DIR = path.resolve(process.cwd(), 'models', 'multimodal_fusion');
export const FUSION_MODEL_JSON_PATH = path.join(FUSION_MODEL_DIR, 'model.json');

export interface MultimodalPredictionOutput {
  meanScore: number;
  epistemicStdDev: number;
  epistemicVariance: number;
  confidence: number;
  ciLower: number;
  ciUpper: number;
  monteCarloSamples: number;
  predictedTier: ClinicalRiskTier;
  tierProbabilities: {
    lowRisk: number;
    moderateNeed: number;
    criticalReferral: number;
  };
  individualScores: number[];
}

/**
 * Late-Fusion Deep Neural Network in TensorFlow.js.
 * Input: 168-d concatenated multimodal vector [128 visual + 32 symptoms + 8 demographics]
 * Architecture:
 *   - Layer 1: Dense(128, 'relu') -> BatchNormalization -> Dropout(0.3)
 *   - Layer 2: Dense(64, 'relu') -> Dropout(0.2)
 *   - Head 1: Dense(1, 'sigmoid', name='risk_score') -> Unified Health Risk Score in [0.0, 1.0]
 *   - Head 2: Dense(3, 'softmax', name='risk_tier') -> [Low Risk, Moderate Need, Critical Referral]
 */
export class MultimodalFusionModel {
  private static cachedModel: tf.LayersModel | null = null;

  /**
   * Constructs the functional multi-head neural network.
   */
  public static buildModel(): tf.LayersModel {
    const input = tf.input({ shape: [FUSION_INPUT_DIM], name: 'multimodal_feature_input' });

    // Layer 1: Dense(128, relu) + BatchNormalization + Dropout(0.3)
    let x = tf.layers.dense({
      units: 128,
      activation: 'relu',
      kernelInitializer: 'glorotNormal',
      name: 'fusion_dense_1'
    }).apply(input) as tf.SymbolicTensor;

    // For single-sample MC Dropout inference with model.apply(..., { training: true }),
    // BatchNormalization must evaluate in inference mode (using moving stats) rather than
    // sample batch statistics (which zero out single-sample activations).
    const bnLayer = tf.layers.batchNormalization({
      name: 'fusion_bn_1'
    });
    const origBnCall = bnLayer.call.bind(bnLayer);
    bnLayer.call = function (inputs: any, kwargs: any) {
      return origBnCall(inputs, { ...kwargs, training: false });
    };

    x = bnLayer.apply(x) as tf.SymbolicTensor;

    x = tf.layers.dropout({
      rate: 0.3,
      name: 'fusion_dropout_1'
    }).apply(x) as tf.SymbolicTensor;


    // Layer 2: Dense(64, relu) + Dropout(0.2)
    x = tf.layers.dense({
      units: 64,
      activation: 'relu',
      kernelInitializer: 'glorotNormal',
      name: 'fusion_dense_2'
    }).apply(x) as tf.SymbolicTensor;

    x = tf.layers.dropout({
      rate: 0.2,
      name: 'fusion_dropout_2'
    }).apply(x) as tf.SymbolicTensor;

    // Output Head 1: Continuous Unified Risk Score [0.0, 1.0]
    const riskScoreHead = tf.layers.dense({
      units: 1,
      activation: 'sigmoid',
      kernelInitializer: 'glorotNormal',
      name: 'risk_score'
    }).apply(x) as tf.SymbolicTensor;

    // Output Head 2: 3-Class Categorical Risk Tier
    const riskTierHead = tf.layers.dense({
      units: CLINICAL_RISK_TIERS.length,
      activation: 'softmax',
      kernelInitializer: 'glorotNormal',
      name: 'risk_tier'
    }).apply(x) as tf.SymbolicTensor;

    const model = tf.model({
      inputs: input,
      outputs: [riskScoreHead, riskTierHead],
      name: 'MultimodalFusionModel'
    });

    model.compile({
      optimizer: tf.train.adam(0.001),
      loss: ['binaryCrossentropy', 'categoricalCrossentropy'],
      metrics: ['mse', 'accuracy']
    });

    return model;
  }

  /**
   * Auto-weight bootstrap: Loads existing checkpoint from disk if present,
   * otherwise compiles new architecture and saves initial weights.
   */
  public static async loadOrBootstrapModel(): Promise<tf.LayersModel> {
    if (this.cachedModel) {
      return this.cachedModel;
    }

    const saveUrl = 'file://./models/multimodal_fusion';
    const loadUrl = 'file://./models/multimodal_fusion/model.json';
    const diskJsonPath = path.resolve(process.cwd(), 'models', 'multimodal_fusion', 'model.json');

    if (fs.existsSync(diskJsonPath) && fs.statSync(diskJsonPath).isFile()) {
      try {
        console.log(`🧬 [MultimodalFusion] Loading model checkpoint from ${loadUrl}...`);
        const model = await tf.loadLayersModel(loadUrl);
        const loadedInputShape = model.inputs[0]?.shape;
        const loadedDim = loadedInputShape ? loadedInputShape[1] : null;
        if (loadedDim && loadedDim !== FUSION_INPUT_DIM) {
          console.warn(`⚠️ [MultimodalFusion] Checkpoint input dimension (${loadedDim}) differs from current (${FUSION_INPUT_DIM}). Rebuilding...`);
          model.dispose();
          throw new Error(`Dimension mismatch: expected ${FUSION_INPUT_DIM}, got ${loadedDim}`);
        }
        this.patchBatchNormInference(model);
        this.cachedModel = model;
        console.log('✅ [MultimodalFusion] Checkpoint loaded successfully.');
        return this.cachedModel;
      } catch (err) {
        console.warn(`⚠️ [MultimodalFusion] Failed to load checkpoint (${err}). Rebuilding...`);
      }
    }

    console.log('🧬 [MultimodalFusion] No checkpoint found. Bootstrapping new Multimodal Fusion architecture...');
    const model = this.buildModel();
    this.patchBatchNormInference(model);

    try {
      if (!fs.existsSync(FUSION_MODEL_DIR)) {
        fs.mkdirSync(FUSION_MODEL_DIR, { recursive: true });
      }
      await model.save(saveUrl);
      console.log(`💾 [MultimodalFusion] Auto-weight bootstrap saved to ${FUSION_MODEL_DIR}`);
    } catch (saveErr) {
      console.warn(`⚠️ [MultimodalFusion] Failed to save bootstrapped weights: ${saveErr}`);
    }

    this.cachedModel = model;
    return model;
  }

  /**
   * Patches any BatchNormalization layers in the model so that during MC Dropout
   * forward passes with `model.apply(..., { training: true })`, BatchNorm evaluates
   * using moving population statistics instead of annihilating single-sample variance.
   */
  public static patchBatchNormInference(model: tf.LayersModel): void {
    for (const layer of model.layers) {
      if (layer.getClassName() === 'BatchNormalization' || layer.name.includes('bn')) {
        const origCall = layer.call.bind(layer);
        layer.call = function (inputs: any, kwargs: any) {
          return origCall(inputs, { ...kwargs, training: false });
        };
      }
    }
  }


  /**
   * Monte Carlo Dropout Inference in TF.js:
   * Enables dropout at inference time using `model.apply(inputTensor, { training: true })`
   * for N passes (default N=10) to sample epistemic uncertainty standard deviations.
   */
  public static async predictWithMCDropout(
    concatenatedVector: number[],
    numSamples = 10
  ): Promise<MultimodalPredictionOutput> {
    if (concatenatedVector.length !== FUSION_INPUT_DIM) {
      throw new Error(
        `Invalid feature vector length: expected ${FUSION_INPUT_DIM}, got ${concatenatedVector.length}`
      );
    }

    const model = await this.loadOrBootstrapModel();

    const scores: number[] = [];
    const tierProbSums: [number, number, number] = [0.0, 0.0, 0.0];

    const inputTensor = tf.tensor2d([concatenatedVector], [1, FUSION_INPUT_DIM], 'float32');

    try {
      for (let i = 0; i < numSamples; i++) {
        // Active dropout during inference: model.apply(inputTensor, { training: true })
        const rawOutputs = model.apply(inputTensor, { training: true });
        const outputs = (Array.isArray(rawOutputs) ? rawOutputs : [rawOutputs]) as tf.Tensor[];

        const scoreTensor = outputs[0];
        const tierTensor = outputs[1];

        const scoreData = await scoreTensor.data();
        const score = scoreData[0];
        scores.push(score);

        if (tierTensor) {
          const tierData = await tierTensor.data();
          tierProbSums[0] += tierData[0];
          tierProbSums[1] += tierData[1];
          tierProbSums[2] += tierData[2];
        }

        // Memory cleanup: dispose all forward pass prediction tensors immediately
        for (const outT of outputs) {
          outT.dispose();
        }
      }
    } finally {
      inputTensor.dispose();
    }

    // Epistemic Uncertainty & Statistics across N stochastic passes
    const meanScore = scores.reduce((sum, s) => sum + s, 0) / numSamples;
    const variance =
      numSamples > 1
        ? scores.reduce((sum, s) => sum + Math.pow(s - meanScore, 2), 0) / (numSamples - 1)
        : 0.0;
    const epistemicStdDev = Math.sqrt(variance);

    // 95% Confidence Interval
    const ciLower = Math.max(0.0, meanScore - 1.96 * epistemicStdDev);
    const ciUpper = Math.min(1.0, meanScore + 1.96 * epistemicStdDev);
    const confidence = Math.max(0.0, Math.min(1.0, 1.0 - 2.0 * epistemicStdDev));

    // Averaged Tier Probabilities
    const avgTierProbs = [
      tierProbSums[0] / numSamples,
      tierProbSums[1] / numSamples,
      tierProbSums[2] / numSamples
    ];

    // Select predicted tier by argmax
    let maxTierIdx = 0;
    for (let j = 1; j < avgTierProbs.length; j++) {
      if (avgTierProbs[j] > avgTierProbs[maxTierIdx]) {
        maxTierIdx = j;
      }
    }

    const predictedTier = CLINICAL_RISK_TIERS[maxTierIdx];

    return {
      meanScore: Number(meanScore.toFixed(4)),
      epistemicStdDev: Number(epistemicStdDev.toFixed(4)),
      epistemicVariance: Number(variance.toFixed(6)),
      confidence: Number(confidence.toFixed(4)),
      ciLower: Number(ciLower.toFixed(4)),
      ciUpper: Number(ciUpper.toFixed(4)),
      monteCarloSamples: numSamples,
      predictedTier,
      tierProbabilities: {
        lowRisk: Number(avgTierProbs[0].toFixed(4)),
        moderateNeed: Number(avgTierProbs[1].toFixed(4)),
        criticalReferral: Number(avgTierProbs[2].toFixed(4))
      },
      individualScores: scores.map(s => Number(s.toFixed(4)))
    };
  }

  /**
   * Resets cached model singleton (used in test teardowns).
   */
  public static resetModel(): void {
    if (this.cachedModel) {
      this.cachedModel.dispose();
      this.cachedModel = null;
    }
  }
}
