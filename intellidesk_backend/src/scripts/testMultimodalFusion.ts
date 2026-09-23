import * as tf from '@tensorflow/tfjs';
import '@tensorflow/tfjs-node';
import {
  VectorAssembler,
  VISUAL_VECTOR_DIM,
  SYMPTOM_VECTOR_DIM,
  DEMOGRAPHICS_VECTOR_DIM,
  TOTAL_CONCATENATED_DIM
} from '../modules/diagnostics/fusion/vectorAssembler.js';
import { MultimodalFusionModel } from '../modules/diagnostics/fusion/MultimodalFusionModel.js';
import {
  assessMultimodalRisk,
  evaluateClinicalSafetyNet
} from '../modules/diagnostics/fusion/assessMultimodalRisk.js';
import { SymptomInputPayload } from '../modules/diagnostics/fusion/types.js';

let passedTests = 0;
let failedTests = 0;

function assert(condition: boolean, message: string): void {
  if (condition) {
    console.log(`  ✅ PASS: ${message}`);
    passedTests++;
  } else {
    console.error(`  ❌ FAIL: ${message}`);
    failedTests++;
  }
}

async function runMultimodalFusionTests(): Promise<void> {
  console.log('\n======================================================');
  console.log('🧪 Starting Multimodal Concatenation & Fusion Test Suite');
  console.log('======================================================\n');

  const initialTensors = tf.memory().numTensors;
  console.log(`Initial TensorFlow tensors allocated: ${initialTensors}`);

  // -----------------------------------------------------------------
  // TEST 1: Strict Min-Max Feature Bounding [0, 1] & Vector Assembly
  // -----------------------------------------------------------------
  console.log('\n--- TEST 1: Strict Min-Max Feature Bounding [0, 1] in VectorAssembler ---');
  {
    // Test with extreme/out-of-bound inputs
    const extremeSymptoms: Partial<SymptomInputPayload> = {
      bodyLocation: 'Left Arm & Skin',
      durationDays: 120, // should cap to 1.0 (since max is 30)
      painScale: 25, // should cap to 1.0 (since max is 10)
      symptoms: ['rash', 'swelling', 'redness', 'fever', 'chills'],
      vitals: {
        heartRate: 250, // extreme high -> cap to 1.0
        temperatureCelsius: 45.0, // extreme high -> cap to 1.0
        systolicBP: 240, // extreme high -> cap to 1.0
        diastolicBP: 150, // extreme high -> cap to 1.0
        oxygenSaturation: 40, // extreme low -> inverted cap to 1.0
        respiratoryRate: 60 // extreme high -> cap to 1.0
      },
      demographics: {
        age: 130, // extreme high -> cap to 1.0
        gender: 'female',
        preExistingConditions: ['diabetes', 'hypertension', 'asthma', 'cardiovascular']
      },
      additionalNotes: 'Severe pruritus and acute trauma'
    };

    const assembled = VectorAssembler.assembleVector(null, extremeSymptoms, extremeSymptoms.vitals);

    assert(
      assembled.dimensions.visual === VISUAL_VECTOR_DIM && assembled.dimensions.visual === 128,
      `Visual vector dimension is 128 (got ${assembled.dimensions.visual})`
    );
    assert(
      assembled.dimensions.symptoms === SYMPTOM_VECTOR_DIM && assembled.dimensions.symptoms === 32,
      `Symptom vector dimension is 32 (got ${assembled.dimensions.symptoms})`
    );
    assert(
      assembled.dimensions.demographics === DEMOGRAPHICS_VECTOR_DIM && assembled.dimensions.demographics === 8,
      `Demographics vector dimension is 8 (got ${assembled.dimensions.demographics})`
    );
    assert(
      assembled.dimensions.total === TOTAL_CONCATENATED_DIM && assembled.dimensions.total === 184,
      `Total concatenated vector dimension is 184 (got ${assembled.dimensions.total})`
    );

    // Verify all 184 features are bounded in [0.0, 1.0]
    let allBounded = true;
    for (let i = 0; i < assembled.concatenatedVector.length; i++) {
      const val = assembled.concatenatedVector[i];
      if (val < 0.0 || val > 1.0 || isNaN(val)) {
        allBounded = false;
        console.error(`Feature at index ${i} out of bounds: ${val}`);
        break;
      }
    }
    assert(allBounded, 'All 184 feature values strictly bounded within [0.0, 1.0]');
  }

  // -----------------------------------------------------------------
  // TEST 2: Text-Only / No-Image Prior Handling
  // -----------------------------------------------------------------
  console.log('\n--- TEST 2: Text-Only / No-Image Prior Handling ---');
  {
    const visualVector = VectorAssembler.buildVisualVector(null);
    const expectedVal = Number((1.0 / Math.sqrt(128)).toFixed(6)); // ~0.088388

    assert(visualVector.length === 128, 'Text-only visual vector length is 128');

    const allMatchUniform = visualVector.every(v => Math.abs(v - expectedVal) < 0.0001);
    assert(
      allMatchUniform,
      `All 128 dimensions filled with uniform L2-normalized constant 1/sqrt(128) ≈ ${expectedVal}`
    );

    // Calculate L2 norm of the uniform vector: sqrt(sum(v_i^2))
    const l2Norm = Math.sqrt(visualVector.reduce((sum, v) => sum + v * v, 0));
    assert(
      Math.abs(l2Norm - 1.0) < 0.001,
      `Text-only uniform vector has unit L2 norm (${l2Norm.toFixed(5)} ≈ 1.0)`
    );
  }

  // -----------------------------------------------------------------
  // TEST 3: Monte Carlo Dropout Activation in TF.js
  // -----------------------------------------------------------------
  console.log('\n--- TEST 3: Monte Carlo Dropout Activation in TF.js (N=10 passes) ---');
  {
    const dummyInput = new Array<number>(TOTAL_CONCATENATED_DIM).fill(0.5);
    const mcResult = await MultimodalFusionModel.predictWithMCDropout(dummyInput, 10);

    assert(mcResult.monteCarloSamples === 10, 'Executed exactly N=10 Monte Carlo stochastic passes');
    assert(
      mcResult.meanScore >= 0.0 && mcResult.meanScore <= 1.0,
      `Mean risk score is within [0.0, 1.0]: ${mcResult.meanScore}`
    );
    assert(
      !isNaN(mcResult.epistemicStdDev) && mcResult.epistemicStdDev >= 0.0,
      `Epistemic uncertainty stdDev computed: ${mcResult.epistemicStdDev}`
    );
    assert(
      !isNaN(mcResult.epistemicVariance) && mcResult.epistemicVariance >= 0.0,
      `Epistemic variance computed: ${mcResult.epistemicVariance}`
    );
    assert(
      mcResult.ciLower <= mcResult.meanScore && mcResult.meanScore <= mcResult.ciUpper,
      `95% Confidence Interval bounds mean: [${mcResult.ciLower} <= ${mcResult.meanScore} <= ${mcResult.ciUpper}]`
    );

    const tierSum =
      mcResult.tierProbabilities.lowRisk +
      mcResult.tierProbabilities.moderateNeed +
      mcResult.tierProbabilities.criticalReferral;
    assert(
      Math.abs(tierSum - 1.0) < 0.02,
      `Output Head 2 tier probabilities sum to 1.0 (${tierSum.toFixed(4)})`
    );
    assert(
      ['Low Risk', 'Moderate Need', 'Critical Referral'].includes(mcResult.predictedTier),
      `Predicted tier is valid: "${mcResult.predictedTier}"`
    );
  }

  // -----------------------------------------------------------------
  // TEST 4: Deterministic Clinical Safety Net
  // -----------------------------------------------------------------
  console.log('\n--- TEST 4: Deterministic Clinical Safety Net Floor (>= 0.85 & Critical) ---');
  {
    // Case A: Red-flag Pain = 10
    const redFlagPain: Partial<SymptomInputPayload> = {
      painScale: 10,
      durationDays: 1,
      symptoms: ['acute headache'],
      vitals: { temperatureCelsius: 37.0, heartRate: 80 }
    };
    const evalA = evaluateClinicalSafetyNet(redFlagPain);
    assert(evalA.triggered, 'Safety Net triggered on Pain Scale = 10');
    assert(evalA.enforcedFloor === 0.85, 'Safety Net enforces minimum floor of 0.85');

    // Case B: Hyperpyrexia Temp = 40.5 C
    const redFlagTemp: Partial<SymptomInputPayload> = {
      painScale: 5,
      durationDays: 2,
      symptoms: ['chills'],
      vitals: { temperatureCelsius: 40.5, heartRate: 95 }
    };
    const evalB = evaluateClinicalSafetyNet(redFlagTemp);
    assert(evalB.triggered, 'Safety Net triggered on Temp >= 40.0°C (40.5°C)');

    // Case C: Chest Pain keyword
    const redFlagChest: Partial<SymptomInputPayload> = {
      bodyLocation: 'Chest',
      painScale: 6,
      durationDays: 1,
      symptoms: ['severe chest pain', 'dizziness'],
      vitals: { temperatureCelsius: 36.8, heartRate: 88 }
    };
    const evalC = evaluateClinicalSafetyNet(redFlagChest);
    assert(evalC.triggered, 'Safety Net triggered on Acute Chest Pain');

    // Case D: Severe Hypoxia SpO2 = 87%
    const redFlagSpo2: Partial<SymptomInputPayload> = {
      painScale: 4,
      durationDays: 3,
      symptoms: ['cough'],
      vitals: { temperatureCelsius: 37.2, heartRate: 85, oxygenSaturation: 87 }
    };
    const evalD = evaluateClinicalSafetyNet(redFlagSpo2);
    assert(evalD.triggered, 'Safety Net triggered on SpO2 < 90%');

    // End-to-End inference with safety net trigger
    const endToEndCritical = await assessMultimodalRisk(null, redFlagChest, redFlagChest.vitals, 10);
    assert(
      endToEndCritical.riskScore >= 0.85,
      `End-to-end score enforced >= 0.85: got ${endToEndCritical.riskScore}`
    );
    assert(
      endToEndCritical.riskTier === 'Critical Referral',
      `End-to-end risk tier forced to "Critical Referral": got "${endToEndCritical.riskTier}"`
    );
    assert(
      endToEndCritical.riskLevel === 'CRITICAL',
      `End-to-end risk level forced to "CRITICAL": got "${endToEndCritical.riskLevel}"`
    );
    assert(
      endToEndCritical.safetyNet?.triggered === true,
      'End-to-end safetyNet.triggered is true'
    );
    assert(
      endToEndCritical.requiresImmediatePhysicianReview === true,
      'requiresImmediatePhysicianReview flagged true'
    );
  }

  // -----------------------------------------------------------------
  // TEST 5: Normal / Low Risk Case (No Safety Net Override)
  // -----------------------------------------------------------------
  console.log('\n--- TEST 5: Mild Non-Emergency Presentation ---');
  {
    const mildSymptoms: Partial<SymptomInputPayload> = {
      bodyLocation: 'Left Forearm',
      painScale: 2,
      durationDays: 2,
      symptoms: ['mild pruritus', 'slight redness'],
      vitals: { temperatureCelsius: 36.8, heartRate: 72, oxygenSaturation: 99 },
      demographics: { age: 28, gender: 'male' }
    };

    const mildResult = await assessMultimodalRisk(null, mildSymptoms, mildSymptoms.vitals, 10);
    assert(
      mildResult.safetyNet?.triggered === false,
      'Safety Net not triggered on mild symptoms'
    );
    assert(
      mildResult.isTextOnlyScreening === true,
      'Correctly flagged as text-only screening'
    );
    assert(
      mildResult.clinicalRecommendations.length > 0,
      'Generated clinical recommendations'
    );
    assert(
      mildResult.differentialDiagnoses.length > 0,
      'Generated differential diagnoses'
    );
  }

  // -----------------------------------------------------------------
  // TEST 6: Memory Safety Check (No Leaked Tensors)
  // -----------------------------------------------------------------
  console.log('\n--- TEST 6: Memory Leak & Tensor Lifecycle Verification ---');
  {
    const beforeTensors = tf.memory().numTensors;
    // Run 5 rapid successive inferences
    for (let r = 0; r < 5; r++) {
      await assessMultimodalRisk(
        null,
        { painScale: 3, durationDays: 1, symptoms: ['mild rash'] },
        undefined,
        10
      );
    }
    const afterTensors = tf.memory().numTensors;
    const leaked = afterTensors - beforeTensors;
    assert(
      leaked === 0,
      `Zero dangling tensors across 5 consecutive multimodal inferences (delta: ${leaked} tensors)`
    );
  }

  console.log('\n======================================================');
  console.log(`📊 Test Summary: ${passedTests} passed, ${failedTests} failed`);
  console.log('======================================================\n');

  if (failedTests > 0) {
    process.exit(1);
  }
}

runMultimodalFusionTests().catch(err => {
  console.error('❌ Unhandled error running test suite:', err);
  process.exit(1);
});
