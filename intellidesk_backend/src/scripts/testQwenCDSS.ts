import 'dotenv/config';
import { QwenInferenceService } from '../modules/cdss/QwenInferenceService.js';
import { CDSSService } from '../modules/cdss/CDSSService.js';
import { CDSSInputPayload, WHO_ICD11_URI_STEM } from '../modules/cdss/types.js';

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

async function runQwenSuite() {
  console.log('\n======================================================');
  console.log('🤖 RUNNING QWEN 2.5 72B INSTRUCT CDSS CLOUD TEST SUITE');
  console.log('======================================================\n');

  // Test 1: Configuration check
  console.log('--- Test 1: Hugging Face Token & Configuration ---');
  assert(QwenInferenceService.isConfigured(), 'QwenInferenceService detected active HF_TOKEN');

  // Test 2: Respiratory Infection Case Prediction via Cloud Inference
  console.log('\n--- Test 2: Respiratory Diagnosis with Qwen/Qwen2.5-72B-Instruct ---');
  const respiratoryPayload: CDSSInputPayload = {
    patientId: 'patient-resp-001',
    multimodalRiskScore: 0.82,
    symptoms: {
      symptoms: ['high fever', 'productive cough with purulent sputum', 'pleuritic chest pain', 'dyspnea'],
      bodyLocation: 'Chest / Thorax',
      painScale: 7,
      durationDays: 4,
      vitals: {
        temperatureCelsius: 39.2,
        heartRate: 112,
        systolicBP: 122,
        diastolicBP: 80,
        oxygenSaturation: 89,
        respirationRate: 28
      }
    },
    audioClassification: {
      predictedCategory: 'Wet/Productive Cough',
      confidence: 0.91
    },
    useCloudModel: true
  };

  const respResult = await QwenInferenceService.predictDisease(respiratoryPayload, 1.25);
  console.log(`    Primary Diagnosis: ${respResult.primaryDiagnosis.code} - ${respResult.primaryDiagnosis.title}`);
  console.log(`    Urgency Level: ${respResult.primaryDiagnosis.urgencyLevel}`);
  console.log(`    Inference Latency: ${respResult.latencyMs}ms`);

  assert(respResult.model === 'Qwen/Qwen2.5-72B-Instruct', 'Model ID confirmed as Qwen/Qwen2.5-72B-Instruct');
  assert(respResult.differentialDiagnoses.length >= 3, 'Generated at least 3 differential diagnoses');
  assert(
    respResult.primaryDiagnosis.code === 'CA40' ||
    respResult.primaryDiagnosis.code.startsWith('1B10') ||
    respResult.primaryDiagnosis.code === 'CA00',
    'Predicted respiratory diagnosis code (CA40 Pneumonia / 1B10 / CA00)',
    `Got: ${respResult.primaryDiagnosis.code}`
  );
  assert(
    respResult.treatmentPathway.recommendedRx.length > 0,
    'Generated evidence-based prescription recommendations'
  );
  assert(
    respResult.treatmentPathway.labOrders.length > 0,
    'Generated clinical lab orders'
  );

  // Test 3: Anatomical Gating on Ocular Intake
  console.log('\n--- Test 3: Ocular Case with Anatomical Gating ---');
  const ocularPayload: CDSSInputPayload = {
    patientId: 'patient-eye-001',
    multimodalRiskScore: 0.35,
    symptoms: {
      symptoms: ['severe eye redness', 'itching / pruritus of eye', 'copious watery ocular discharge'],
      bodyLocation: 'Eye / Ophthalmology',
      vitals: {
        temperatureCelsius: 36.9,
        heartRate: 70,
        oxygenSaturation: 99,
        respirationRate: 16
      }
    },
    useCloudModel: true
  };

  const ocularResult = await QwenInferenceService.predictDisease(ocularPayload, 1.25);
  console.log(`    Top Ocular Diagnosis: ${ocularResult.primaryDiagnosis.code} - ${ocularResult.primaryDiagnosis.title}`);

  const respCandidate = ocularResult.differentialDiagnoses.find(
    (d) => d.code === '1B10.0' || d.code === 'CA00' || d.category === 'Respiratory Diseases'
  );
  if (respCandidate) {
    assert(
      respCandidate.probability === 0.0,
      'Purely respiratory candidate masked to strict 0.0% probability on ocular presentation'
    );
  }

  // Test 4: End-to-End CDSSService Integration
  console.log('\n--- Test 4: End-to-End CDSSService Cloud Evaluation ---');
  const e2eResult = await CDSSService.evaluateScreening(respiratoryPayload);
  assert(e2eResult.modelUsed === 'Qwen/Qwen2.5-72B-Instruct', 'CDSSService marked modelUsed as Qwen/Qwen2.5-72B-Instruct');
  assert(e2eResult.primaryICD11Uri.startsWith(WHO_ICD11_URI_STEM), 'Primary ICD-11 URI conforms to WHO MMS stem');
  assert(e2eResult.treatmentPathway !== undefined, 'Treatment pathway successfully formulated');

  // Test 5: Graceful Local Fallback when useCloudModel is false
  console.log('\n--- Test 5: Offline / Local Fallback Enforcement ---');
  const localResult = await CDSSService.evaluateScreening({
    ...respiratoryPayload,
    useCloudModel: false
  });
  assert(
    localResult.modelUsed?.includes('Neural') || localResult.modelUsed?.includes('Ensemble'),
    'Falls back cleanly to local Neural Ensemble when cloud model disabled',
    `Got: ${localResult.modelUsed}`
  );

  console.log('\n======================================================');
  console.log(`🎉 ALL ${passed}/${total} QWEN CLOUD CDSS TESTS PASSED!`);
  console.log('======================================================\n');
}

runQwenSuite().catch((err) => {
  console.error('💥 Qwen CDSS Suite Failed:', err);
  process.exit(1);
});
