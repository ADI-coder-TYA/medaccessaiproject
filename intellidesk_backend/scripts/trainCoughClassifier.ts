import * as tf from '@tensorflow/tfjs';
import '@tensorflow/tfjs-node';
import * as fs from 'fs';
import * as path from 'path';
import { ACOUSTIC_MEANS, ACOUSTIC_STDS } from '../src/modules/diagnostics/audio/types.js';

const AUDIO_FEATURE_DIM = 16;
const NUM_CLASSES = 4;
const COUGH_MODEL_DIR = path.resolve(process.cwd(), 'models', 'cough_classifier');

// Helper: Gaussian random generator (Box-Muller)
function randomGaussian(mean: number, stdDev: number): number {
  let u = 0, v = 0;
  while (u === 0) u = Math.random();
  while (v === 0) v = Math.random();
  const num = Math.sqrt(-2.0 * Math.log(u)) * Math.cos(2.0 * Math.PI * v);
  return mean + num * stdDev;
}

function clamp(val: number, min = -4.0, max = 4.0): number {
  return Math.min(max, Math.max(min, val));
}

/**
 * Generates strictly balanced (25% per class) clinical acoustic dataset with Z-Score standardization:
 * - Class 0: Normal Respiratory / Non-Pathological Phonation (humming, quiet breath, speaking)
 * - Class 1: Dry / Irritative Cough (explosive attack, elevated flux & ZCR, wideband turbulence)
 * - Class 2: Wet / Productive Cough (secretory lower resonance, bubbling flux bursts, elevated low MFCCs)
 * - Class 3: Wheeze / Stridor (high-frequency musical whistling, elevated centroid & ZCR)
 */
function generateDataset(samplesPerClass = 5000) {
  const xs: number[][] = [];
  const ys: number[][] = [];
  const smoothingAlpha = 0.12; // Label smoothing: 0.91 for true class, 0.03 for others

  for (let c = 0; c < NUM_CLASSES; c++) {
    for (let i = 0; i < samplesPerClass; i++) {
      const raw = new Array<number>(AUDIO_FEATURE_DIM).fill(0);

      // Label smoothed target distribution (strictly balanced 1:1:1:1)
      const target = [
        smoothingAlpha / NUM_CLASSES,
        smoothingAlpha / NUM_CLASSES,
        smoothingAlpha / NUM_CLASSES,
        smoothingAlpha / NUM_CLASSES
      ];
      target[c] = (1.0 - smoothingAlpha) + (smoothingAlpha / NUM_CLASSES);

      if (c === 0) {
        // --- CLASS 0: NORMAL RESPIRATORY / HUMMING / PHONATION ---
        const subType = Math.random();
        if (subType < 0.5) {
          // Humming / sustained phonation
          raw[12] = randomGaussian(0.08, 0.025); // Centroid: low
          raw[13] = randomGaussian(0.10, 0.03);  // Rolloff: low
          raw[14] = randomGaussian(0.012, 0.005); // Flux: very low (steady)
          raw[15] = randomGaussian(0.045, 0.015); // ZCR: low
          // MFCCs: steady decaying harmonics
          const baseMfcc = [32.0, 18.0, 7.0, -1.0, -8.0, -13.0, -15.0, -14.0, -11.0, -7.0, -3.0, 1.0];
          for (let m = 0; m < 12; m++) raw[m] = randomGaussian(baseMfcc[m], 2.5);
        } else {
          // Normal ambient breathing
          raw[12] = randomGaussian(0.12, 0.035);
          raw[13] = randomGaussian(0.16, 0.04);
          raw[14] = randomGaussian(0.018, 0.007);
          raw[15] = randomGaussian(0.060, 0.02);
          const baseMfcc = [24.0, 12.0, 4.0, -3.0, -9.0, -12.0, -13.0, -11.0, -8.0, -5.0, -2.0, 0.0];
          for (let m = 0; m < 12; m++) raw[m] = randomGaussian(baseMfcc[m], 3.0);
        }
      } else if (c === 1) {
        // --- CLASS 1: DRY / IRRITATIVE COUGH ---
        // Explosive burst: elevated centroid (0.20-0.34), high flux (0.06-0.14), turbulent ZCR (0.10-0.22)
        raw[12] = randomGaussian(0.24, 0.045);
        raw[13] = randomGaussian(0.38, 0.06);
        raw[14] = randomGaussian(0.085, 0.025);
        raw[15] = randomGaussian(0.140, 0.035);
        // MFCCs: flat wideband energy across higher bands
        const baseMfcc = [16.0, 8.0, 2.0, -2.0, -5.0, -7.0, -8.0, -7.0, -5.0, -3.0, -1.0, 0.0];
        for (let m = 0; m < 12; m++) raw[m] = randomGaussian(baseMfcc[m], 3.0);
      } else if (c === 2) {
        // --- CLASS 2: WET / PRODUCTIVE COUGH ---
        // Secretory lower resonance: centroid ~0.15, rolloff ~0.24, flux bursts ~0.075, low MFCCs elevated
        raw[12] = randomGaussian(0.15, 0.035);
        raw[13] = randomGaussian(0.24, 0.05);
        raw[14] = randomGaussian(0.075, 0.022);
        raw[15] = randomGaussian(0.085, 0.025);
        // MFCCs: strong low-frequency acoustic energy
        const baseMfcc = [34.0, 18.0, 8.0, 0.0, -6.0, -11.0, -13.0, -12.0, -9.0, -5.0, -2.0, 0.5];
        for (let m = 0; m < 12; m++) raw[m] = randomGaussian(baseMfcc[m], 2.8);
      } else if (c === 3) {
        // --- CLASS 3: WHEEZE / STRIDOR ---
        // Continuous high-pitched musical whistling: high centroid (~0.38), high rolloff (~0.52), high ZCR (~0.22)
        raw[12] = randomGaussian(0.38, 0.06);
        raw[13] = randomGaussian(0.52, 0.07);
        raw[14] = randomGaussian(0.035, 0.012); // Tonal, steady whistling
        raw[15] = randomGaussian(0.220, 0.045);
        // MFCCs: distinct harmonic peak in mid-to-high coefficients
        const baseMfcc = [14.0, 7.0, 1.0, -1.0, -3.0, 2.0, 5.0, 2.0, -1.0, -2.0, -1.0, 0.0];
        for (let m = 0; m < 12; m++) raw[m] = randomGaussian(baseMfcc[m], 2.5);
      }

      // Apply Z-Score feature standardization matching AudioFeatureExtractor
      const standardized = new Array<number>(AUDIO_FEATURE_DIM).fill(0);
      for (let j = 0; j < AUDIO_FEATURE_DIM; j++) {
        const z = (raw[j] - ACOUSTIC_MEANS[j]) / (ACOUSTIC_STDS[j] || 1.0);
        // Add subtle sensor noise jitter
        const jittered = z + randomGaussian(0, 0.03);
        standardized[j] = clamp(jittered, -4.0, 4.0);
      }

      xs.push(standardized);
      ys.push(target);
    }
  }

  // Shuffle dataset (Fisher-Yates)
  for (let i = xs.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [xs[i], xs[j]] = [xs[j], xs[i]];
    [ys[i], ys[j]] = [ys[j], ys[i]];
  }

  return {
    xs: tf.tensor2d(xs, [xs.length, AUDIO_FEATURE_DIM]),
    ys: tf.tensor2d(ys, [ys.length, NUM_CLASSES]),
    count: xs.length
  };
}

export async function trainAndSaveCoughClassifier() {
  console.log('🎙️ [CoughClassifier Training] Generating 20,000 strictly balanced (1:1:1:1) Z-Score standardized samples...');
  const data = generateDataset(5000);
  console.log(`✅ Generated ${data.count} samples across 4 respiratory acoustic classes.`);

  // Regularized Model Architecture: Dense(48) -> BN -> Dropout(0.25) -> Dense(24) -> Dropout(0.20) -> Dense(4, softmax)
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
    units: NUM_CLASSES,
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

  console.log('🚀 [CoughClassifier Training] Training regularized model for 35 epochs...');
  await model.fit(data.xs, data.ys, {
    epochs: 35,
    batchSize: 64,
    validationSplit: 0.25,
    shuffle: true,
    callbacks: {
      onEpochEnd: (epoch, logs) => {
        if ((epoch + 1) % 10 === 0 || epoch === 34) {
          console.log(`Epoch ${epoch + 1}/35 - loss: ${logs?.loss.toFixed(4)} - acc: ${(Number(logs?.acc) * 100).toFixed(1)}% - val_loss: ${logs?.val_loss?.toFixed(4)} - val_acc: ${(Number(logs?.val_acc) * 100).toFixed(1)}%`);
        }
      }
    }
  });

  // Evaluate on specific standardized test vectors
  console.log('\n🔍 [Model Verification] Testing Distinct Standardized Vectors:');

  // Test Case A: Humming (Class 0)
  const rawHum = [32.0, 18.0, 7.0, -1.0, -8.0, -13.0, -15.0, -14.0, -11.0, -7.0, -3.0, 1.0, 0.08, 0.10, 0.012, 0.045];
  const humVector = rawHum.map((v, idx) => clamp((v - ACOUSTIC_MEANS[idx]) / ACOUSTIC_STDS[idx]));
  const humTensor = tf.tensor2d([humVector], [1, 16]);
  const humPred = (model.predict(humTensor) as tf.Tensor).dataSync();
  console.log('Test A (Humming):', {
    Normal: (humPred[0] * 100).toFixed(1) + '%',
    Dry: (humPred[1] * 100).toFixed(1) + '%',
    Wet: (humPred[2] * 100).toFixed(1) + '%',
    Wheeze: (humPred[3] * 100).toFixed(1) + '%'
  });

  // Test Case B: Real Dry Cough (Class 1)
  const rawDry = [16.0, 8.0, 2.0, -2.0, -5.0, -7.0, -8.0, -7.0, -5.0, -3.0, -1.0, 0.0, 0.24, 0.38, 0.085, 0.140];
  const dryVector = rawDry.map((v, idx) => clamp((v - ACOUSTIC_MEANS[idx]) / ACOUSTIC_STDS[idx]));
  const dryTensor = tf.tensor2d([dryVector], [1, 16]);
  const dryPred = (model.predict(dryTensor) as tf.Tensor).dataSync();
  console.log('Test B (Dry Cough):', {
    Normal: (dryPred[0] * 100).toFixed(1) + '%',
    Dry: (dryPred[1] * 100).toFixed(1) + '%',
    Wet: (dryPred[2] * 100).toFixed(1) + '%',
    Wheeze: (dryPred[3] * 100).toFixed(1) + '%'
  });

  // Test Case C: Real Wet Cough (Class 2)
  const rawWet = [34.0, 18.0, 8.0, 0.0, -6.0, -11.0, -13.0, -12.0, -9.0, -5.0, -2.0, 0.5, 0.15, 0.24, 0.075, 0.085];
  const wetVector = rawWet.map((v, idx) => clamp((v - ACOUSTIC_MEANS[idx]) / ACOUSTIC_STDS[idx]));
  const wetTensor = tf.tensor2d([wetVector], [1, 16]);
  const wetPred = (model.predict(wetTensor) as tf.Tensor).dataSync();
  console.log('Test C (Wet Cough):', {
    Normal: (wetPred[0] * 100).toFixed(1) + '%',
    Dry: (wetPred[1] * 100).toFixed(1) + '%',
    Wet: (wetPred[2] * 100).toFixed(1) + '%',
    Wheeze: (wetPred[3] * 100).toFixed(1) + '%'
  });

  // Test Case D: Wheeze (Class 3)
  const rawWheeze = [14.0, 7.0, 1.0, -1.0, -3.0, 2.0, 5.0, 2.0, -1.0, -2.0, -1.0, 0.0, 0.38, 0.52, 0.035, 0.220];
  const wheezeVector = rawWheeze.map((v, idx) => clamp((v - ACOUSTIC_MEANS[idx]) / ACOUSTIC_STDS[idx]));
  const wheezeTensor = tf.tensor2d([wheezeVector], [1, 16]);
  const wheezePred = (model.predict(wheezeTensor) as tf.Tensor).dataSync();
  console.log('Test D (Wheeze):', {
    Normal: (wheezePred[0] * 100).toFixed(1) + '%',
    Dry: (wheezePred[1] * 100).toFixed(1) + '%',
    Wet: (wheezePred[2] * 100).toFixed(1) + '%',
    Wheeze: (wheezePred[3] * 100).toFixed(1) + '%'
  });

  // Save trained weights to disk
  if (!fs.existsSync(COUGH_MODEL_DIR)) {
    fs.mkdirSync(COUGH_MODEL_DIR, { recursive: true });
  }
  const saveUrl = `file://${COUGH_MODEL_DIR.replace(/\\/g, '/')}`;
  await model.save(saveUrl);
  console.log(`💾 [CoughClassifier Training] Successfully trained and saved model checkpoint to ${saveUrl}`);

  data.xs.dispose();
  data.ys.dispose();
  humTensor.dispose();
  dryTensor.dispose();
  wetTensor.dispose();
  wheezeTensor.dispose();
  model.dispose();
}

trainAndSaveCoughClassifier().catch(console.error);
