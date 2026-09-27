import * as tf from '@tensorflow/tfjs';
import '@tensorflow/tfjs-node';
import { DiseasePredictionModel } from '../modules/diagnostics/fusion/diseasePredictionModel.js';
import { MultimodalFusionModel } from '../modules/diagnostics/fusion/MultimodalFusionModel.js';
import { CoughClassifier } from '../modules/diagnostics/audio/CoughClassifier.js';
import { ClinicalMobileNetBuilder } from '../modules/diagnostics/vision/clinicalMobileNet.js';

async function trainAllModels() {
  console.log('================================================================');
  console.log('🚀 COMMENCING LARGE-SCALE CLINICAL DEEP LEARNING MODEL TRAINING');
  console.log('================================================================\n');

  const startTime = Date.now();

  // 1. Cough Classifier (6,000 acoustic cases)
  console.log('--- [1/4] Training Acoustic Biomarker Neural Network (6,000 samples) ---');
  const t1 = Date.now();
  await CoughClassifier.trainAndPersistModel(6000);
  console.log(`✓ Cough Classifier training completed in ${((Date.now() - t1) / 1000).toFixed(1)}s\n`);

  // 2. Multimodal Late-Fusion Network (12,000 multimodal cases)
  console.log('--- [2/4] Training Multi-Head Multimodal Late-Fusion Network (12,000 samples) ---');
  const t2 = Date.now();
  await MultimodalFusionModel.trainAndPersistModel(12000);
  console.log(`✓ Multimodal Fusion Network training completed in ${((Date.now() - t2) / 1000).toFixed(1)}s\n`);

  // 3. Clinical MobileNetV3 (400 clinical vision cases)
  console.log('--- [3/4] Training Clinical MobileNetV3 Vision Network (400 images) ---');
  const t3 = Date.now();
  await ClinicalMobileNetBuilder.trainAndPersistModel(400);
  console.log(`✓ Clinical MobileNetV3 training completed in ${((Date.now() - t3) / 1000).toFixed(1)}s\n`);

  // 4. Disease Prediction Deep Classifier (14,950 clinical cases across 23 WHO ICD-11 classes)
  console.log('--- [4/4] Training Disease Prediction Deep Classifier (14,950 samples) ---');
  const t4 = Date.now();
  await DiseasePredictionModel.trainAndPersistModel(650);
  console.log(`✓ Disease Prediction Classifier training completed in ${((Date.now() - t4) / 1000).toFixed(1)}s\n`);

  const totalTime = ((Date.now() - startTime) / 1000).toFixed(1);
  console.log('================================================================');
  console.log(`🎉 ALL 4 CLINICAL MODELS SUCCESSFULLY TRAINED & PERSISTED TO DISK (${totalTime}s)`);
  console.log('================================================================');
}

trainAllModels().catch(err => {
  console.error('❌ Model training pipeline failed:', err);
  process.exit(1);
});
