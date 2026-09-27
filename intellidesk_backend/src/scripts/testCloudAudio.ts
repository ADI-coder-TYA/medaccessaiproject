import 'dotenv/config';
import { CloudAudioClassifier } from '../modules/diagnostics/audio/CloudAudioClassifier.js';
import { CoughClassifier } from '../modules/diagnostics/audio/CoughClassifier.js';
import { COUGH_CATEGORIES } from '../modules/diagnostics/audio/types.js';

let passed = 0;
let total = 0;

function assert(condition: boolean, testName: string, details?: string) {
  total++;
  if (condition) {
    passed++;
    console.log(`  ✅ [PASS] ${testName}`);
  } else {
    console.error(`  ❌ [FAIL] ${testName}${details ? ` -> ${details}` : ''}`);
    throw new Error(`Test failed: ${testName}`);
  }
}

async function runCloudAudioSuite() {
  console.log('\n======================================================');
  console.log('🎙️ RUNNING HUGGING FACE CLOUD AUDIO CLASSIFIER TEST SUITE');
  console.log('======================================================\n');

  // Test 1: Configuration check
  console.log('--- Test 1: Hugging Face Cloud Configuration ---');
  assert(CloudAudioClassifier.isCloudConfigured(), 'CloudAudioClassifier detected active HF_TOKEN');

  // Test 2: High-Pitched Wheeze / Stridor Detection via HF Cloud
  console.log('\n--- Test 2: Wheeze / Stridor Classification via Cloud Inference ---');
  // Wheeze signature: high centroid, high rolloff, harmonic formants
  const wheezeVector = [
    18.5, 9.2, -1.8, 5.2, -7.0, -9.2, -10.0, -8.5, -5.5, -3.0, 1.0, 1.5,
    0.68, // Centroid > 0.50 (musical wheezing)
    0.75, // Rolloff
    0.19, // Flux
    0.24  // ZCR
  ];

  const wheezeResult = await CloudAudioClassifier.classify(wheezeVector);
  console.log(`    Predicted: "${wheezeResult.predictedCategory}" (${(wheezeResult.confidence * 100).toFixed(1)}%)`);
  console.log(`    Probabilities:`, JSON.stringify(wheezeResult.probabilities));
  console.log(`    Red Flag: ${wheezeResult.isRedFlagRespiratory} | Reason: ${wheezeResult.redFlagReason}`);

  assert(COUGH_CATEGORIES.includes(wheezeResult.predictedCategory), 'Predicted category is valid respiratory category');
  assert(wheezeResult.probabilities.wheezeStridor > 0.40, 'Elevated wheeze/stridor probability for wheeze acoustic vector');
  assert(wheezeResult.isRedFlagRespiratory === true, 'Red flag respiratory warning triggered for wheezing/stridor');
  assert(typeof wheezeResult.latencyMs === 'number' && wheezeResult.latencyMs > 0, 'Latency measured');

  // Test 3: Normal Phonation / Soft Breathing Sound
  console.log('\n--- Test 3: Normal Respiratory Sound via Cloud Inference ---');
  const normalVector = [
    32.0, 18.0, 7.0, -1.0, -8.0, -13.0, -15.0, -14.0, -11.0, -7.0, -3.0, 1.0,
    0.08, // Low centroid (soft breath)
    0.10, // Low rolloff
    0.012, // Low flux
    0.045  // Low ZCR
  ];

  const normalResult = await CloudAudioClassifier.classify(normalVector);
  console.log(`    Predicted: "${normalResult.predictedCategory}" (${(normalResult.confidence * 100).toFixed(1)}%)`);
  console.log(`    Probabilities:`, JSON.stringify(normalResult.probabilities));

  assert(normalResult.probabilities.normalRespiratory > 0.40, 'Normal respiratory probability dominant for soft airflow');
  assert(normalResult.isRedFlagRespiratory === false, 'No red flag triggered for normal respiratory breathing');

  // Test 4: Local Model Fallback Verification
  console.log('\n--- Test 4: Local Model Fallback Verification ---');
  const localDirect = await CoughClassifier.classify(wheezeVector);
  assert(localDirect !== undefined, 'Local CoughClassifier executes reliably');
  assert(COUGH_CATEGORIES.includes(localDirect.predictedCategory), 'Local classifier produces valid category');

  console.log('\n======================================================');
  console.log(`🎉 ALL ${passed}/${total} CLOUD AUDIO CLASSIFIER TESTS PASSED!`);
  console.log('======================================================\n');
}

runCloudAudioSuite().catch((err) => {
  console.error('💥 Cloud Audio Suite Failed:', err);
  process.exit(1);
});
