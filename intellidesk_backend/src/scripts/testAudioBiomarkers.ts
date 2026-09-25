import * as tf from '@tensorflow/tfjs';
import '@tensorflow/tfjs-node';
import { AudioFeatureExtractor } from '../modules/diagnostics/audio/AudioFeatureExtractor.js';
import { CoughClassifier } from '../modules/diagnostics/audio/CoughClassifier.js';
import { VectorAssembler } from '../modules/diagnostics/fusion/vectorAssembler.js';
import { assessMultimodalRisk, evaluateClinicalSafetyNet } from '../modules/diagnostics/fusion/assessMultimodalRisk.js';
import {
  TARGET_SAMPLE_RATE,
  AUDIO_FEATURE_DIM,
  ACOUSTIC_MEANS,
  ACOUSTIC_STDS
} from '../modules/diagnostics/audio/types.js';
import { TOTAL_CONCATENATED_DIM } from '../modules/diagnostics/fusion/vectorAssembler.js';

let passed = 0;
let failed = 0;

function assert(condition: boolean, message: string) {
  if (condition) {
    console.log(`  ✅ PASS: ${message}`);
    passed++;
  } else {
    console.error(`  ❌ FAIL: ${message}`);
    failed++;
  }
}

/**
 * Creates a valid synthetic PCM WAV buffer in memory for testing
 */
function createSyntheticWavBuffer(sampleRate: number, durationSeconds: number, frequencyHz: number): Buffer {
  const numSamples = Math.floor(sampleRate * durationSeconds);
  const buffer = Buffer.alloc(44 + numSamples * 2);

  buffer.write('RIFF', 0);
  buffer.writeUInt32LE(36 + numSamples * 2, 4);
  buffer.write('WAVE', 8);
  buffer.write('fmt ', 12);
  buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20); // PCM
  buffer.writeUInt16LE(1, 22); // mono
  buffer.writeUInt32LE(sampleRate, 24);
  buffer.writeUInt32LE(sampleRate * 2, 28);
  buffer.writeUInt16LE(2, 32);
  buffer.writeUInt16LE(16, 34);
  buffer.write('data', 36);
  buffer.writeUInt32LE(numSamples * 2, 40);

  for (let i = 0; i < numSamples; i++) {
    const sample = Math.sin(2 * Math.PI * frequencyHz * (i / sampleRate)) * 16000;
    buffer.writeInt16LE(Math.floor(sample), 44 + i * 2);
  }

  return buffer;
}

async function runAudioBiomarkerTests() {
  console.log('\n======================================================');
  console.log('🧪 Starting Audio Biomarker & Cough Classifier Test Suite');
  console.log('======================================================');

  // --------------------------------------------------------------------------
  // TEST 1: Audio Feature Extraction & Resampling
  // --------------------------------------------------------------------------
  console.log('\n--- TEST 1: Mandatory 16 kHz Mono Resampling & Feature Extraction ---');

  // 1a. Native 16 kHz WAV extraction
  const wav16k = createSyntheticWavBuffer(16000, 1.0, 440);
  const result16k = await AudioFeatureExtractor.extractFeatures(wav16k);

  assert(result16k.featureVector.length === AUDIO_FEATURE_DIM, `Feature vector has exactly ${AUDIO_FEATURE_DIM} dimensions`);
  assert(result16k.resampledRate === TARGET_SAMPLE_RATE, `Standardized to target ${TARGET_SAMPLE_RATE} Hz`);
  assert(!result16k.isResampled, '16 kHz input requires zero resampling');
  assert(result16k.durationSeconds >= 0.95 && result16k.durationSeconds <= 1.05, `Duration measured accurately: ${result16k.durationSeconds}s`);

  // Verify all 16 features are Z-score standardized and bounded in [-4.0, +4.0]
  const allBounded = result16k.featureVector.every(v => v >= -4.0 && v <= 4.0 && !isNaN(v));
  assert(allBounded, 'Z-Score Standardization: All 16 features bounded in [-4.0, 4.0] without NaN');

  // 1b. 44.1 kHz WAV input with Mandatory Resampling
  const wav44k = createSyntheticWavBuffer(44100, 1.0, 1200);
  const result44k = await AudioFeatureExtractor.extractFeatures(wav44k);
  assert(result44k.isResampled === true, 'Mandatory Resampling: 44.1 kHz input automatically resampled');
  assert(result44k.resampledRate === TARGET_SAMPLE_RATE, 'Resampled output rate strictly equals 16000 Hz');
  assert(result44k.featureVector.every(v => v >= -4.0 && v <= 4.0 && !isNaN(v)), 'Resampled features standardized and bounded');

  // 1c. Guardrail check: empty or silent buffer throws expected error
  let guardrailCaught = false;
  try {
    await AudioFeatureExtractor.extractFeatures(Buffer.alloc(0));
  } catch (err: any) {
    if (err.message.includes('Invalid Audio Stream')) {
      guardrailCaught = true;
    }
  }
  assert(guardrailCaught, 'Guardrail: Empty/zero audio buffer rejected with "Invalid Audio Stream"');

  // 1d. Guardrail: Silent audio (RMS < 0.01) rejected
  const silentWav = createSyntheticWavBuffer(16000, 1.0, 440);
  for (let i = 44; i < silentWav.length; i++) silentWav[i] = 0;
  let silentCaught = false;
  try {
    await AudioFeatureExtractor.extractFeatures(silentWav);
  } catch (err: any) {
    if (err.message.includes('No cough sound detected')) {
      silentCaught = true;
    }
  }
  assert(silentCaught, 'Guardrail: Silent buffer (RMS < 0.01) rejected with "No cough sound detected"');

  // --------------------------------------------------------------------------
  // TEST 2: Cough Classification in TensorFlow.js & Dynamic Non-Collapsed Output
  // --------------------------------------------------------------------------
  console.log('\n--- TEST 2: CoughClassifier Multi-Class Inference & Dynamic Probabilities ---');

  const model = await CoughClassifier.loadOrBootstrapModel();
  assert(model !== null, 'CoughClassifier TF.js model loaded successfully');
  assert(model.inputs[0].shape[1] === AUDIO_FEATURE_DIM, `Model input layer accepts [null, ${AUDIO_FEATURE_DIM}]`);

  // Classify standard extraction vector
  const classification = await CoughClassifier.classify(result16k.featureVector);
  assert(typeof classification.predictedCategory === 'string', `Predicted category: "${classification.predictedCategory}"`);
  assert(classification.confidence > 0 && classification.confidence <= 1.0, `Confidence score in [0, 1]: ${(classification.confidence * 100).toFixed(1)}%`);

  const sumProbs =
    classification.probabilities.normalRespiratory +
    classification.probabilities.dryIrritativeCough +
    classification.probabilities.wetProductiveCough +
    classification.probabilities.wheezeStridor;
  assert(Math.abs(sumProbs - 1.0) < 0.01, `Softmax class probabilities sum to 1.0 (${sumProbs.toFixed(4)})`);

  // Test Guardrail: All-zero tensor rejected
  let zeroGuardrailCaught = false;
  try {
    await CoughClassifier.classify(new Array<number>(16).fill(0.0));
  } catch (err: any) {
    if (err.message.includes('Invalid Audio Stream')) {
      zeroGuardrailCaught = true;
    }
  }
  assert(zeroGuardrailCaught, 'Guardrail: All-zero tensor rejected with "Invalid Audio Stream: Zero/NaN buffer received from DSP"');

  // Dynamic Probabilities Test: Verify 2 distinct acoustic vectors produce distinct classes, NOT locked 64.1%
  // Vector A: Low-pitch humming phonation
  const rawHum = [32.0, 18.0, 7.0, -1.0, -8.0, -13.0, -15.0, -14.0, -11.0, -7.0, -3.0, 1.0, 0.08, 0.10, 0.012, 0.045];
  const humVector = rawHum.map((v, idx) => Math.max(-4, Math.min(4, (v - ACOUSTIC_MEANS[idx]) / ACOUSTIC_STDS[idx])));
  const humClf = await CoughClassifier.classify(humVector);
  assert(humClf.predictedCategory === 'Normal Respiratory', `Vector A correctly classified as Normal Respiratory (${(humClf.confidence * 100).toFixed(1)}%)`);
  assert(Math.abs(humClf.confidence - 0.641) > 0.10, `Confidence is dynamic (${(humClf.confidence * 100).toFixed(1)}%), NOT locked to 64.1%`);

  // Vector B: High-frequency explosive Dry Cough
  const rawDry = [16.0, 8.0, 2.0, -2.0, -5.0, -7.0, -8.0, -7.0, -5.0, -3.0, -1.0, 0.0, 0.24, 0.38, 0.085, 0.140];
  const dryVector = rawDry.map((v, idx) => Math.max(-4, Math.min(4, (v - ACOUSTIC_MEANS[idx]) / ACOUSTIC_STDS[idx])));
  const dryClf = await CoughClassifier.classify(dryVector);
  assert(dryClf.predictedCategory === 'Dry/Irritative Cough', `Vector B correctly classified as Dry/Irritative Cough (${(dryClf.confidence * 100).toFixed(1)}%)`);
  assert(Math.abs(dryClf.confidence - 0.641) > 0.10, `Confidence is dynamic (${(dryClf.confidence * 100).toFixed(1)}%), NOT locked to 64.1%`);

  // Vector C: Musical Wheeze / Stridor
  const rawWheeze = [14.0, 7.0, 1.0, -1.0, -3.0, 2.0, 5.0, 2.0, -1.0, -2.0, -1.0, 0.0, 0.38, 0.52, 0.035, 0.220];
  const wheezeVector = rawWheeze.map((v, idx) => Math.max(-4, Math.min(4, (v - ACOUSTIC_MEANS[idx]) / ACOUSTIC_STDS[idx])));
  const wheezeClf = await CoughClassifier.classify(wheezeVector);
  assert(wheezeClf.predictedCategory === 'Wheeze/Stridor', `Vector C correctly classified as Wheeze/Stridor (${(wheezeClf.confidence * 100).toFixed(1)}%)`);

  // --------------------------------------------------------------------------
  // TEST 3: VectorAssembler Expansion to 184 Dimensions
  // --------------------------------------------------------------------------
  console.log('\n--- TEST 3: VectorAssembler Expansion to 184-d Fusion Tensor ---');

  assert(TOTAL_CONCATENATED_DIM === 184, 'TOTAL_CONCATENATED_DIM expanded from 168 to 184');

  const dummyVision = new Array<number>(128).fill(0.088388);
  const dummySymptoms = { painScale: 5, durationDays: 3, symptoms: ['cough', 'wheezing'] };
  const dummyVitals = { temperatureCelsius: 37.8, heartRate: 88 };

  const assembled184 = VectorAssembler.assembleVector(
    dummyVision,
    dummySymptoms,
    dummyVitals,
    result16k.featureVector
  );

  assert(assembled184.concatenatedVector.length === 184, `Assembled vector length is 184 (actual: ${assembled184.concatenatedVector.length})`);
  assert(assembled184.dimensions.visual === 128, 'Visual subvector = 128');
  assert(assembled184.dimensions.symptoms === 32, 'Symptoms subvector = 32');
  assert(assembled184.dimensions.demographics === 8, 'Demographics subvector = 8');
  assert(assembled184.dimensions.audio === 16, 'Audio subvector = 16');

  // No-audio prior assembly
  const assembledNoAudio = VectorAssembler.assembleVector(dummyVision, dummySymptoms, dummyVitals, null);
  assert(assembledNoAudio.concatenatedVector.length === 184, 'No-audio prior produces exact 184-d vector');

  // --------------------------------------------------------------------------
  // TEST 4: Wheeze / Stridor Red-Flag Floor (>= 0.75)
  // --------------------------------------------------------------------------
  console.log('\n--- TEST 4: Wheeze / Stridor Red-Flag Floor (Guardrail 3) ---');

  const highWheezeClassification = {
    predictedCategory: 'Wheeze/Stridor' as const,
    confidence: 0.82,
    probabilities: {
      normalRespiratory: 0.05,
      dryIrritativeCough: 0.05,
      wetProductiveCough: 0.08,
      wheezeStridor: 0.82
    },
    isRedFlagRespiratory: true,
    featureVector: wheezeVector
  };

  const safetyEvaluation = evaluateClinicalSafetyNet(
    { painScale: 2, symptoms: ['mild cough'] },
    { temperatureCelsius: 36.8 },
    highWheezeClassification
  );

  assert(safetyEvaluation.triggered === true, 'Wheeze/Stridor >= 70% triggers safety net');
  assert(safetyEvaluation.enforcedFloor === 0.75, `Safety net enforces minimum risk score floor >= 0.75 (actual: ${safetyEvaluation.enforcedFloor})`);
  assert(safetyEvaluation.isRespiratoryRedFlag === true, 'Flagged isRespiratoryRedFlag = true');

  // End-to-end risk assessment with Wheeze red-flag
  const riskResult = await assessMultimodalRisk({
    symptomData: { painScale: 2, symptoms: ['cough'] },
    audioClassification: highWheezeClassification,
    patientVitals: { temperatureCelsius: 36.8 }
  });

  assert(riskResult.riskScore >= 0.75, `Final risk score elevated to >= 0.75 floor (actual: ${riskResult.riskScore})`);
  assert(riskResult.riskLevel === 'CRITICAL', 'Risk level elevated to CRITICAL due to respiratory red flag');
  assert(Boolean(riskResult.safetyNet?.reasons?.some(r => r.includes('Respiratory Red Flag'))), 'Safety net reasons include Respiratory Red Flag');

  // --------------------------------------------------------------------------
  // TEST 5: Memory Safety & Zero Tensor Leaks
  // --------------------------------------------------------------------------
  console.log('\n--- TEST 5: Memory Safety (Zero Leaked Tensors) ---');

  const initialTensors = tf.memory().numTensors;
  for (let i = 0; i < 3; i++) {
    await CoughClassifier.classify(result16k.featureVector);
  }
  const finalTensors = tf.memory().numTensors;
  assert(finalTensors === initialTensors, `0 tensor leaks across 3 consecutive classifications (${initialTensors} -> ${finalTensors})`);

  console.log('\n======================================================');
  console.log(`📊 Audio Biomarker Test Summary: ${passed} passed, ${failed} failed`);
  console.log('======================================================\n');

  if (failed > 0) {
    process.exit(1);
  }
}

runAudioBiomarkerTests().catch(err => {
  console.error('Fatal test error:', err);
  process.exit(1);
});
