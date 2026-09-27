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
   * Trains ClinicalMobileNet on a synthetic dataset of realistic clinical lesion patterns,
   * fitting both classification probabilities and bottleneck embedding heads.
   */
  public static async trainAndPersistModel(sampleCount = 400): Promise<tf.LayersModel> {
    console.log(`🩺 [ClinicalMobileNet] Training Clinical MobileNetV3 on ${sampleCount} image samples...`);
    const model = this.buildModel();

    const samplesPerClass = Math.floor(sampleCount / 4);
    const totalPixels = INPUT_IMAGE_SIZE * INPUT_IMAGE_SIZE * 3;
    const xData = new Float32Array(sampleCount * totalPixels);
    const yClfData = new Float32Array(sampleCount * CLINICAL_VISION_CLASSES.length);
    const yEmbedData = new Float32Array(sampleCount * BOTTLENECK_EMBEDDING_DIM);

    let sampleIdx = 0;

    for (let c = 0; c < 4; c++) {
      for (let s = 0; s < samplesPerClass; s++) {
        const imgOffset = sampleIdx * totalPixels;

        // Realistic clinical data augmentation: spatial center jitter, illumination scaling, skin phototypes
        const skinTone = Math.random();
        const baseSkinR = skinTone < 0.33 ? 0.30 : (skinTone < 0.66 ? 0.15 : -0.15);
        const baseSkinG = skinTone < 0.33 ? 0.10 : (skinTone < 0.66 ? 0.00 : -0.30);
        const baseSkinB = skinTone < 0.33 ? -0.10 : (skinTone < 0.66 ? -0.20 : -0.40);
        const centerX = INPUT_IMAGE_SIZE / 2 + (Math.random() - 0.5) * 24;
        const centerY = INPUT_IMAGE_SIZE / 2 + (Math.random() - 0.5) * 24;
        const illumination = 0.92 + Math.random() * 0.16;

        // Generate synthetic lesion patterns per class
        for (let y = 0; y < INPUT_IMAGE_SIZE; y++) {
          for (let x = 0; x < INPUT_IMAGE_SIZE; x++) {
            const pixelIdx = imgOffset + (y * INPUT_IMAGE_SIZE + x) * 3;
            const dx = (x - centerX) / (INPUT_IMAGE_SIZE / 2);
            const dy = (y - centerY) / (INPUT_IMAGE_SIZE / 2);
            const distFromCenter = Math.sqrt(dx * dx + dy * dy);
            const noise = (Math.random() - 0.5) * 0.10;

            let r: number, g: number, b: number;
            if (c === 0) {
              // Normal/Benign: Healthy skin tone across diverse phototypes
              r = baseSkinR + noise;
              g = baseSkinG + noise;
              b = baseSkinB + noise;
            } else if (c === 1) {
              // Mild Inflammation: Erythematous flush, diffuse redness
              r = Math.min(0.85, baseSkinR + 0.40) + noise;
              g = baseSkinG - 0.10 + noise;
              b = baseSkinB - 0.10 + noise;
            } else if (c === 2) {
              // Acute Infection/Lesion: Center yellowish purulent exudate + hot erythematous rim
              if (distFromCenter < 0.35) {
                r = 0.65 + noise;
                g = 0.35 + noise;
                b = -0.30 + noise;
              } else if (distFromCenter < 0.65) {
                r = Math.min(0.90, baseSkinR + 0.55) + noise;
                g = baseSkinG - 0.20 + noise;
                b = baseSkinB - 0.20 + noise;
              } else {
                r = baseSkinR + noise;
                g = baseSkinG + noise;
                b = baseSkinB + noise;
              }
            } else {
              // Severe/Emergency: Necrotic dark violaceous ulceration / ischemic eschar
              if (distFromCenter < 0.45) {
                r = -0.55 + noise;
                g = -0.70 + noise;
                b = -0.60 + noise;
              } else if (distFromCenter < 0.75) {
                r = 0.65 + noise;
                g = -0.35 + noise;
                b = -0.15 + noise; // Violaceous purpura rim
              } else {
                r = baseSkinR + noise;
                g = baseSkinG + noise;
                b = baseSkinB + noise;
              }
            }

            xData[pixelIdx] = Math.max(-1.0, Math.min(1.0, r * illumination));
            xData[pixelIdx + 1] = Math.max(-1.0, Math.min(1.0, g * illumination));
            xData[pixelIdx + 2] = Math.max(-1.0, Math.min(1.0, b * illumination));
          }
        }

        // Calibrated label smoothing: 0.94 for target, 0.02 for others
        const clfOffset = sampleIdx * CLINICAL_VISION_CLASSES.length;
        for (let k = 0; k < CLINICAL_VISION_CLASSES.length; k++) {
          yClfData[clfOffset + k] = k === c ? 0.94 : 0.02;
        }

        // Target bottleneck embedding (128-D) with intra-class variance
        const embedOffset = sampleIdx * BOTTLENECK_EMBEDDING_DIM;
        const segmentStart = c * 32;
        let sumSq = 0;
        for (let dim = 0; dim < BOTTLENECK_EMBEDDING_DIM; dim++) {
          let val = (Math.random() - 0.5) * 0.08;
          if (dim >= segmentStart && dim < segmentStart + 32) {
            val += 0.5 + Math.random() * 0.3;
          }
          yEmbedData[embedOffset + dim] = val;
          sumSq += val * val;
        }
        const norm = Math.sqrt(sumSq) || 1.0;
        for (let dim = 0; dim < BOTTLENECK_EMBEDDING_DIM; dim++) {
          yEmbedData[embedOffset + dim] /= norm;
        }

        sampleIdx++;
      }
    }

    // Fisher-Yates pre-shuffle for I.I.D. train/validation split across all 4 visual classes
    const indices = Array.from({ length: sampleCount }, (_, i) => i);
    for (let i = sampleCount - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      const temp = indices[i];
      indices[i] = indices[j];
      indices[j] = temp;
    }

    const shuffledX = new Float32Array(sampleCount * totalPixels);
    const shuffledClf = new Float32Array(sampleCount * CLINICAL_VISION_CLASSES.length);
    const shuffledEmbed = new Float32Array(sampleCount * BOTTLENECK_EMBEDDING_DIM);
    for (let i = 0; i < sampleCount; i++) {
      const orig = indices[i];
      shuffledX.set(xData.subarray(orig * totalPixels, (orig + 1) * totalPixels), i * totalPixels);
      shuffledClf.set(yClfData.subarray(orig * CLINICAL_VISION_CLASSES.length, (orig + 1) * CLINICAL_VISION_CLASSES.length), i * CLINICAL_VISION_CLASSES.length);
      shuffledEmbed.set(yEmbedData.subarray(orig * BOTTLENECK_EMBEDDING_DIM, (orig + 1) * BOTTLENECK_EMBEDDING_DIM), i * BOTTLENECK_EMBEDDING_DIM);
    }

    const xTensor = tf.tensor4d(shuffledX, [sampleCount, INPUT_IMAGE_SIZE, INPUT_IMAGE_SIZE, 3]);
    const yClfTensor = tf.tensor2d(shuffledClf, [sampleCount, CLINICAL_VISION_CLASSES.length]);
    const yEmbedTensor = tf.tensor2d(shuffledEmbed, [sampleCount, BOTTLENECK_EMBEDDING_DIM]);

    console.log(`🩺 [ClinicalMobileNet] Fitting MobileNetV3 multi-head graph (${sampleCount} images, 15 epochs)...`);
    await model.fit(xTensor, [yClfTensor, yEmbedTensor], {
      epochs: 15,
      batchSize: 16,
      shuffle: true,
      validationSplit: 0.15,
      verbose: 0,
      callbacks: {
        onEpochEnd: (epoch: number, logs?: tf.Logs) => {
          if ((epoch + 1) % 5 === 0 || epoch === 14) {
            console.log(`  [Epoch ${epoch + 1}/15] Loss: ${logs?.loss?.toFixed(4)} | Clf Acc: ${(Number(logs?.classification_probabilities_acc ?? 0) * 100).toFixed(1)}% | Embed MSE: ${logs?.bottleneck_embedding_loss?.toFixed(4)}`);
          }
        }
      }
    });

    xTensor.dispose();
    yClfTensor.dispose();
    yEmbedTensor.dispose();

    if (!fs.existsSync(MODEL_DIR)) {
      fs.mkdirSync(MODEL_DIR, { recursive: true });
    }
    const saveUrl = `file://${MODEL_DIR.replace(/\\/g, '/')}`;
    await model.save(saveUrl);
    console.log(`💾 [ClinicalMobileNet] Trained model saved to ${saveUrl}`);
    return model;
  }

  /**
   * Auto-weight bootstrap: Loads model weights from disk if available,
   * otherwise trains on synthetic clinical image dataset and persists checkpoints.
   */
  public static async loadOrBootstrapModel(forceTrain = false): Promise<tf.LayersModel> {
    const saveUrl = `file://${MODEL_DIR.replace(/\\/g, '/')}`;
    const loadUrl = fs.existsSync(MODEL_JSON_PATH)
      ? `file://${MODEL_JSON_PATH.replace(/\\/g, '/')}`
      : 'file://./models/clinical_vision/model.json';
    const diskJsonPath = MODEL_JSON_PATH;

    if (!forceTrain && fs.existsSync(diskJsonPath) && fs.statSync(diskJsonPath).isFile()) {
      try {
        console.log(`🩺 [ClinicalMobileNet] Loading checkpoint from ${loadUrl}...`);
        const model = await tf.loadLayersModel(loadUrl);
        console.log('✅ [ClinicalMobileNet] Checkpoint loaded successfully.');
        return model;
      } catch (err) {
        console.warn(`⚠️ [ClinicalMobileNet] Failed to load existing model from disk (${err}). Retraining...`);
      }
    }

    console.log('🩺 [ClinicalMobileNet] Bootstrapping and training new MobileNetV3 architecture...');
    const model = await this.trainAndPersistModel(400);
    return model;
  }
}
