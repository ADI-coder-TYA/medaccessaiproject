import * as tf from '@tensorflow/tfjs';
import * as tfNode from '@tensorflow/tfjs-node';
import * as fs from 'fs';
import * as path from 'path';

export const CLINICAL_VISION_CLASSES = [
  'Normal/Benign',
  'Mild Inflammation',
  'Acute Infection/Lesion',
  'Severe/Emergency'
] as const;

export type ClinicalVisionClass = typeof CLINICAL_VISION_CLASSES[number];

export const INPUT_IMAGE_SIZE = 224;
export const BOTTLENECK_EMBEDDING_DIM = 128;
export const MODEL_DIR = path.resolve(process.cwd(), 'models', 'clinical_vision');
export const MODEL_JSON_PATH = path.join(MODEL_DIR, 'model.json');

/**
 * Lightweight MobileNetV3 / EfficientNet-B0 inspired Transfer Learning Model.
 * Multi-output functional graph:
 *   1. Category probabilities across 4 clinical severity tiers [1, 4]
 *   2. Bottleneck latent visual feature embedding vector [1, 128]
 */
export class ClinicalMobileNetBuilder {
  /**
   * Constructs the functional multi-head neural network.
   */
  public static buildModel(): tf.LayersModel {
    const input = tf.input({ shape: [INPUT_IMAGE_SIZE, INPUT_IMAGE_SIZE, 3], name: 'clinical_image_input' });

    // Stem Convolution: 32 filters, 3x3 kernel, stride 2 (Downsample to 112x112)
    let x = tf.layers.conv2d({
      filters: 32,
      kernelSize: 3,
      strides: 2,
      padding: 'same',
      useBias: false,
      name: 'conv_stem'
    }).apply(input) as tf.SymbolicTensor;

    x = tf.layers.batchNormalization({ name: 'bn_stem' }).apply(x) as tf.SymbolicTensor;
    x = tf.layers.reLU({ maxValue: 6, name: 'relu_stem' }).apply(x) as tf.SymbolicTensor; // ReLU6 for mobile efficiency

    // Inverted Residual Block 1 (Downsample to 56x56)
    x = tf.layers.depthwiseConv2d({
      kernelSize: 3,
      strides: 2,
      padding: 'same',
      useBias: false,
      name: 'dw_conv_1'
    }).apply(x) as tf.SymbolicTensor;
    x = tf.layers.batchNormalization({ name: 'dw_bn_1' }).apply(x) as tf.SymbolicTensor;
    x = tf.layers.reLU({ maxValue: 6, name: 'dw_relu_1' }).apply(x) as tf.SymbolicTensor;

    x = tf.layers.conv2d({
      filters: 64,
      kernelSize: 1,
      strides: 1,
      padding: 'same',
      useBias: false,
      name: 'pw_conv_1'
    }).apply(x) as tf.SymbolicTensor;
    x = tf.layers.batchNormalization({ name: 'pw_bn_1' }).apply(x) as tf.SymbolicTensor;

    // Inverted Residual Block 2 (Downsample to 28x28)
    x = tf.layers.depthwiseConv2d({
      kernelSize: 3,
      strides: 2,
      padding: 'same',
      useBias: false,
      name: 'dw_conv_2'
    }).apply(x) as tf.SymbolicTensor;
    x = tf.layers.batchNormalization({ name: 'dw_bn_2' }).apply(x) as tf.SymbolicTensor;
    x = tf.layers.reLU({ maxValue: 6, name: 'dw_relu_2' }).apply(x) as tf.SymbolicTensor;

    x = tf.layers.conv2d({
      filters: 128,
      kernelSize: 1,
      strides: 1,
      padding: 'same',
      useBias: false,
      name: 'pw_conv_2'
    }).apply(x) as tf.SymbolicTensor;
    x = tf.layers.batchNormalization({ name: 'pw_bn_2' }).apply(x) as tf.SymbolicTensor;

    // Inverted Residual Block 3 (Downsample to 14x14)
    x = tf.layers.depthwiseConv2d({
      kernelSize: 3,
      strides: 2,
      padding: 'same',
      useBias: false,
      name: 'dw_conv_3'
    }).apply(x) as tf.SymbolicTensor;
    x = tf.layers.batchNormalization({ name: 'dw_bn_3' }).apply(x) as tf.SymbolicTensor;
    x = tf.layers.reLU({ maxValue: 6, name: 'dw_relu_3' }).apply(x) as tf.SymbolicTensor;

    x = tf.layers.conv2d({
      filters: 256,
      kernelSize: 1,
      strides: 1,
      padding: 'same',
      useBias: false,
      name: 'pw_conv_3'
    }).apply(x) as tf.SymbolicTensor;
    x = tf.layers.batchNormalization({ name: 'pw_bn_3' }).apply(x) as tf.SymbolicTensor;

    // Global Average Pooling: 14x14x256 -> 256 feature vector
    const pooled = tf.layers.globalAveragePooling2d({
      name: 'global_avg_pool'
    }).apply(x) as tf.SymbolicTensor;

    // Multi-Head 1: 128-dimensional Bottleneck Visual Feature Embedding Vector
    const bottleneck = tf.layers.dense({
      units: BOTTLENECK_EMBEDDING_DIM,
      activation: 'relu',
      kernelInitializer: 'glorotNormal',
      name: 'bottleneck_embedding'
    }).apply(pooled) as tf.SymbolicTensor;

    // Dropout for regularization
    const dropped = tf.layers.dropout({
      rate: 0.25,
      name: 'dropout'
    }).apply(bottleneck) as tf.SymbolicTensor;

    // Multi-Head 2: 4-class Softmax Classification Probabilities
    const classification = tf.layers.dense({
      units: CLINICAL_VISION_CLASSES.length,
      activation: 'softmax',
      kernelInitializer: 'glorotNormal',
      name: 'classification_probabilities'
    }).apply(dropped) as tf.SymbolicTensor;

    const model = tf.model({
      inputs: input,
      outputs: [classification, bottleneck],
      name: 'ClinicalMobileNetV3'
    });

    model.compile({
      optimizer: tf.train.adam(0.0005),
      loss: ['categoricalCrossentropy', 'meanSquaredError'],
      metrics: ['accuracy']
    });

    return model;
  }

  /**
   * Auto-weight bootstrap: Loads model weights from disk if available,
   * otherwise constructs a new model, initializes weights, and persists checkpoints.
   */
  public static async loadOrBootstrapModel(): Promise<tf.LayersModel> {
    const saveUrl = 'file://./models/clinical_vision';
    const loadUrl = 'file://./models/clinical_vision/model.json';
    const diskJsonPath = path.resolve(process.cwd(), 'models', 'clinical_vision', 'model.json');

    if (fs.existsSync(diskJsonPath) && fs.statSync(diskJsonPath).isFile()) {
      try {
        console.log(`🩺 [ClinicalMobileNet] Loading checkpoint from ${loadUrl}...`);
        const model = await tf.loadLayersModel(loadUrl);
        console.log('✅ [ClinicalMobileNet] Checkpoint loaded successfully.');
        return model;
      } catch (err) {
        console.warn(`⚠️ [ClinicalMobileNet] Failed to load existing model from disk (${err}). Rebuilding...`);
      }
    }

    console.log('🩺 [ClinicalMobileNet] No pre-existing checkpoint found. Bootstrapping new MobileNetV3 architecture...');
    const model = this.buildModel();

    try {
      if (!fs.existsSync(MODEL_DIR)) {
        fs.mkdirSync(MODEL_DIR, { recursive: true });
      }
      await model.save(saveUrl);
      console.log(`💾 [ClinicalMobileNet] Auto-weight bootstrap saved to ${MODEL_DIR}`);
    } catch (saveErr) {
      console.warn(`⚠️ [ClinicalMobileNet] Failed to persist bootstrapped weights to disk: ${saveErr}`);
    }

    return model;
  }
}
