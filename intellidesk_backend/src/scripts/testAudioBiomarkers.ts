import 'dotenv/config';
import * as tf from '@tensorflow/tfjs';
import '@tensorflow/tfjs-node';
import { AudioFeatureExtractor } from '../modules/diagnostics/audio/AudioFeatureExtractor.js';
import { CoughClassifier } from '../modules/diagnostics/audio/CoughClassifier.js';
import { VectorAssembler, TOTAL_CONCATENATED_DIM } from '../modules/diagnostics/fusion/vectorAssembler.js';
import { assessMultimodalRisk, evaluateClinicalSafetyNet } from '../modules/diagnostics/fusion/assessMultimodalRisk.js';
import { TARGET_SAMPLE_RATE, AUDIO_FEATURE_DIM } from '../modules/diagnostics/audio/types.js';

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
 * Creates a valid RIFF/WAV mono 16-bit PCM audio buffer.
 */
function createSyntheticWavBuffer(sampleRate: number, durationSeconds: number, frequencyHz: number): Buffer {
  const numSamples = Math.floor(sampleRate * durationSeconds);
  const dataSize = numSamples * 2; // 16-bit = 2 bytes per sample
  const headerSize = 44;
  const buffer = Buffer.alloc(headerSize + dataSize);

  // RIFF Chunk Descriptor
  buffer.write('RIFF', 0);
  buffer.writeUInt32LE(36 + dataSize, 4);
  buffer.write('WAVE', 8);

  // "fmt " sub-chunk
  buffer.write('fmt ', 12);
  buffer.writeUInt32LE(16, 16); // Subchunk1Size (16 for PCM)
  buffer.writeUInt16LE(1, 20);  // AudioFormat (1 for PCM)
  buffer.writeUInt16LE(1, 22);  // NumChannels (1 for mono)
  buffer.writeUInt32LE(sampleRate, 24); // SampleRate
  buffer.writeUInt32LE(sampleRate * 2, 28); // ByteRate (SampleRate * NumChannels * BitsPerSample/8)
  buffer.writeUInt16LE(2, 32);  // BlockAlign
  buffer.writeUInt16LE(16, 34); // BitsPerSample

  // "data" sub-chunk
  buffer.write('data', 36);
  buffer.writeUInt32LE(dataSize, 40);

  // Generate synthetic audio wave (modulated frequency with cough burst transients)
  for (let i = 0; i < numSamples; i++) {
    const t = i / sampleRate;
    // Burst envelope with harmonics
    const burst = Math.exp(-Math.pow((t - durationSeconds * 0.4) * 5, 2));
    const sampleVal = Math.sin(2 * Math.PI * frequencyHz * t) * (0.4 + 0.6 * burst);
    const int16 = Math.max(-32767, Math.min(32767, Math.round(sampleVal * 32000)));
    buffer.writeInt16LE(int16, headerSize + i * 2);
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

  // Verify all 16 features strictly bounded in [0.0, 1.0] (Guardrail 2)
  const allBounded = result16k.featureVector.every(v => v >= 0.0 && v <= 1.0);
  assert(allBounded, 'Strict Acoustic Feature Scaling: All 16 features bounded in [0.0, 1.0]');

  // 1b. 44.1 kHz WAV input with Mandatory Resampling (Guardrail 1)
  const wav44k = createSyntheticWavBuffer(44100, 1.0, 1200);
  const result44k = await AudioFeatureExtractor.extractFeatures(wav44k);
  assert(result44k.isResampled === true, 'Mandatory Resampling: 44.1 kHz input automatically resampled');
  assert(result44k.resampledRate === TARGET_SAMPLE_RATE, 'Resampled output rate strictly equals 16000 Hz');
  assert(result44k.featureVector.every(v => v >= 0.0 && v <= 1.0), 'Resampled features strictly bounded in [0.0, 1.0]');

  // 1c. Neutral Acoustic Prior (Empty / Silent input)
  const emptyResult = await AudioFeatureExtractor.extractFeatures(null);
  assert(emptyResult.featureVector.length === AUDIO_FEATURE_DIM, 'Neutral prior vector has 16 dimensions');
  assert(emptyResult.featureVector.every(v => v === 0.25), 'Neutral prior fills uniform 1/sqrt(16) = 0.25');

  // --------------------------------------------------------------------------
  // TEST 2: Cough Classification in TensorFlow.js
  // --------------------------------------------------------------------------
  console.log('\n--- TEST 2: CoughClassifier Multi-Class Inference ---');

  const model = await CoughClassifier.loadOrBootstrapModel();
  assert(model !== null, 'CoughClassifier TF.js model loaded successfully');
  assert(model.inputs[0].shape[1] === AUDIO_FEATURE_DIM, `Model input layer accepts [null, ${AUDIO_FEATURE_DIM}]`);

  // Classify synthetic acoustic vector
  const classification = await CoughClassifier.classify(result16k.featureVector);
  assert(typeof classification.predictedCategory === 'string', `Predicted category: "${classification.predictedCategory}"`);
  assert(classification.confidence > 0 && classification.confidence <= 1.0, `Confidence score in [0, 1]: ${(classification.confidence * 100).toFixed(1)}%`);

  const sumProbs =
    classification.probabilities.normalRespiratory +
    classification.probabilities.dryIrritativeCough +
    classification.probabilities.wetProductiveCough +
    classification.probabilities.wheezeStridor;
  assert(Math.abs(sumProbs - 1.0) < 0.01, `Softmax class probabilities sum to 1.0 (${sumProbs.toFixed(4)})`);

  // Wheeze / Stridor simulated pattern
  const wheezeVector = new Array<number>(AUDIO_FEATURE_DIM).fill(0.3);
  wheezeVector[12] = 0.88; // High spectral centroid (high-pitch squeak/stridor)
  wheezeVector[15] = 0.85; // High zero-crossing rate (turbulent airway)
  const wheezeClf = await CoughClassifier.classify(wheezeVector);
  assert(wheezeClf.predictedCategory !== undefined, 'Wheeze/Stridor pattern classified successfully');

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
  assert(assembled184.concatenatedVector.every(v => v >= 0.0 && v <= 1.0), 'All 184 multimodal features strictly bounded in [0.0, 1.0]');

  // No-audio prior assembly
  const assembledNoAudio = VectorAssembler.assembleVector(dummyVision, dummySymptoms, dummyVitals, null);
  assert(assembledNoAudio.concatenatedVector.length === 184, 'No-audio prior produces exact 184-d vector');
  const audioSlice = assembledNoAudio.concatenatedVector.slice(168);
  assert(audioSlice.every(v => v === 0.25), 'No-audio subvector populated with neutral acoustic prior 0.25');

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
