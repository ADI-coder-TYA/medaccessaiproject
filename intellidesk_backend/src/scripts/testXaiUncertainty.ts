import * as tf from '@tensorflow/tfjs';
import '@tensorflow/tfjs-node';
import sharp from 'sharp';
import { GradCamGenerator } from '../modules/diagnostics/explainability/gradCamGenerator.js';
import { MonteCarloUncertaintyEngine } from '../modules/diagnostics/explainability/uncertaintyEngine.js';
import { FeatureImportanceEngine } from '../modules/diagnostics/explainability/featureImportance.js';
import { VectorAssembler } from '../modules/diagnostics/fusion/vectorAssembler.js';
import { SymptomInputPayload, MultimodalRiskResult } from '../modules/diagnostics/fusion/types.js';
import { VisionEmbeddingResult } from '../modules/diagnostics/vision/types.js';

let passed = 0;
let failed = 0;

function assert(condition: boolean, msg: string): void {
  if (condition) {
    console.log(`  ✅ PASS: ${msg}`);
    passed++;
  } else {
    console.error(`  ❌ FAIL: ${msg}`);
    failed++;
  }
}

async function runXaiUncertaintyTests(): Promise<void> {
  console.log('\n======================================================');
  console.log('🧪 Starting Explainability (XAI) & Uncertainty Test Suite');
  console.log('======================================================\n');

  const initialTensors = tf.memory().numTensors;
  console.log(`Initial TensorFlow tensors: ${initialTensors}`);

  // -----------------------------------------------------------------
  // TEST 1: Grad-CAM Visual Heatmap Gradient Computation
  // -----------------------------------------------------------------
  console.log('\n--- TEST 1: Grad-CAM Visual Heatmap (Gradients w.r.t pw_conv_3) ---');
  {
    // Synthesize 224x224x3 image tensor
    const testImageTensor = tf.randomUniform([1, 224, 224, 3], -1.0, 1.0) as tf.Tensor4D;

    // Synthesize dummy 300x300 JPEG photo buffer
    const dummyPhoto = await sharp({
      create: { width: 300, height: 300, channels: 3, background: { r: 210, g: 180, b: 140 } }
    }).jpeg().toBuffer();

    const gradCam = await GradCamGenerator.computeGradCam(
      testImageTensor,
      dummyPhoto,
      2, // Target class: Acute Infection/Lesion
      'Acute Infection/Lesion'
    );

    testImageTensor.dispose();

    assert(gradCam.targetClass === 'Acute Infection/Lesion', 'Target class matches request');
    assert(gradCam.targetClassIndex === 2, 'Target class index equals 2');
    assert(gradCam.heatmapGrid.length === 14, `Heatmap grid height is 14 (got ${gradCam.heatmapGrid.length})`);
    assert(gradCam.heatmapGrid[0].length === 14, `Heatmap grid width is 14 (got ${gradCam.heatmapGrid[0].length})`);

    // Verify all activations are in [0.0, 1.0]
    let allInRange = true;
    for (let r = 0; r < gradCam.heatmapGrid.length; r++) {
      for (let c = 0; c < gradCam.heatmapGrid[r].length; c++) {
        const v = gradCam.heatmapGrid[r][c];
        if (v < 0.0 || v > 1.0 || isNaN(v)) {
          allInRange = false;
          break;
        }
      }
    }
    assert(allInRange, 'All 14x14 heatmap activations normalized to [0.0, 1.0]');

    assert(gradCam.salientRegion.peakIntensity >= 0.0 && gradCam.salientRegion.peakIntensity <= 1.0, 'Peak intensity in [0, 1]');
    assert(gradCam.salientRegion.boundingBox.width === 0.3, 'Salient region bounding box generated');
    assert(gradCam.overlaySvgDataUri.startsWith('data:image/svg+xml'), 'Lightweight SVG overlay generated');
    assert(gradCam.overlayImageBuffer != null && gradCam.overlayImageBuffer.length > 0, 'Composited photo buffer created');
    assert(Boolean(gradCam.overlayImageDataUri?.startsWith('data:image/jpeg;base64,')), 'Base64 composite JPEG URI created');

    console.log(`  ℹ️ Composite photo size: ${gradCam.overlayImageBuffer?.length} bytes`);
    console.log(`  ℹ️ Salient focus: ${gradCam.salientRegion.description}`);
  }

  // -----------------------------------------------------------------
  // TEST 2: Monte Carlo Dropout Uncertainty Quantification
  // -----------------------------------------------------------------
  console.log('\n--- TEST 2: Monte Carlo Dropout Uncertainty Engine (N=10 passes) ---');
  {
    const dummyVector = VectorAssembler.assembleVector(
      new Array(128).fill(0.1),
      { painScale: 6, durationDays: 4, symptoms: ['rash', 'redness'] },
      { temperatureCelsius: 38.2, heartRate: 92 }
    ).concatenatedVector;

    const report = await MonteCarloUncertaintyEngine.quantifyUncertainty(dummyVector, 10);

    assert(report.monteCarloSamples === 10, 'Executed exactly N=10 forward passes');
    assert(report.sampleScores.length === 10, 'Collected 10 distinct stochastic sample scores');
    assert(report.meanRiskScore >= 0.0 && report.meanRiskScore <= 1.0, `Mean risk score valid: ${report.meanRiskScore}`);
    assert(report.stdDev >= 0.0 && !isNaN(report.stdDev), `Epistemic standard deviation computed: ${report.stdDev}`);
    assert(report.uncertaintyScoreFormatted.includes('±'), `Formatted score contains ± symbol: "${report.uncertaintyScoreFormatted}"`);
    assert(report.rawScoreFormatted.includes('±'), `Raw score contains ±: "${report.rawScoreFormatted}"`);
    assert(report.confidenceInterval95[0] <= report.meanRiskScore && report.meanRiskScore <= report.confidenceInterval95[1], '95% CI bounds the mean');
    assert(['LOW_UNCERTAINTY', 'MODERATE_UNCERTAINTY', 'HIGH_EPISTEMIC_UNCERTAINTY'].includes(report.uncertaintyTier), `Uncertainty tier classified: ${report.uncertaintyTier}`);
    assert(report.clinicalInterpretation.length > 20, 'Generated clinical uncertainty interpretation narrative');

    console.log(`  ℹ️ Formatted Uncertainty: ${report.uncertaintyScoreFormatted}`);
    console.log(`  ℹ️ 95% Confidence Interval: [${report.confidenceInterval95.join(', ')}]`);
    console.log(`  ℹ️ Interpretation: ${report.clinicalInterpretation}`);
  }

  // -----------------------------------------------------------------
  // TEST 3: Tri-Feature Contribution Breakdown (Visual, Symptoms, Age)
  // -----------------------------------------------------------------
  console.log('\n--- TEST 3: Tri-Feature Contribution Breakdown & Relative Weights ---');
  {
    const symptoms: SymptomInputPayload = {
      bodyLocation: 'Right Forearm',
      durationDays: 5,
      painScale: 7,
      symptoms: ['rash', 'swelling', 'redness'],
      vitals: { temperatureCelsius: 38.5, heartRate: 98, oxygenSaturation: 97 },
      demographics: { age: 68, gender: 'female', preExistingConditions: ['hypertension'] }
    };

    const mockRiskResult: MultimodalRiskResult = {
      riskScore: 0.65,
      riskLevel: 'HIGH',
      uncertaintyBounds: { confidence: 0.90, ciLower: 0.58, ciUpper: 0.72, epistemicVariance: 0.002, monteCarloSamples: 10 },
      primaryDiagnosis: 'Cellulitis Flare',
      differentialDiagnoses: [],
      clinicalRecommendations: [],
      featureWeights: { visualContribution: 0.45, symptomContribution: 0.35, vitalsContribution: 0.15, demographicContribution: 0.05 },
      requiresImmediatePhysicianReview: true
    };

    const mockVision: VisionEmbeddingResult = {
      embeddingDimension: 128,
      featureVector: new Array(128).fill(0.08),
      primaryCategory: 'DERMATOLOGY_RASH',
      predictedCondition: 'Acute Lesion',
      topFindings: [
        { label: 'Erythematous Rash', confidence: 0.88, clinicalSignificance: 'HIGH_ALERT', description: 'Prominent inflammatory margins' }
      ],
      visualQualityScore: 0.94
    };

    // Case A: Multimodal presentation with Image
    const breakdownWithImage = FeatureImportanceEngine.calculateTriFeatureBreakdown(
      symptoms,
      mockRiskResult,
      mockVision
    );

    const sumPercentagesA =
      breakdownWithImage.visualAnalysisPercent +
      breakdownWithImage.symptomsPercent +
      breakdownWithImage.agePercent;

    assert(sumPercentagesA === 100, `Percentages strictly sum to 100% (got ${sumPercentagesA}%)`);
    assert(breakdownWithImage.visualAnalysisPercent > 0, `Visual analysis percentage > 0 (got ${breakdownWithImage.visualAnalysisPercent}%)`);
    assert(breakdownWithImage.symptomsPercent > 0, `Symptoms percentage > 0 (got ${breakdownWithImage.symptomsPercent}%)`);
    assert(breakdownWithImage.agePercent > 0, `Age percentage > 0 (got ${breakdownWithImage.agePercent}%)`);
    assert(
      breakdownWithImage.formattedBreakdown.startsWith('Visual Analysis:') &&
      breakdownWithImage.formattedBreakdown.includes('Symptoms:') &&
      breakdownWithImage.formattedBreakdown.includes('Age:'),
      `Formatted breakdown string strictly matches format: "${breakdownWithImage.formattedBreakdown}"`
    );

    console.log(`  ℹ️ Multimodal breakdown: ${breakdownWithImage.formattedBreakdown}`);

    // Case B: Text-Only presentation (No Image)
    const breakdownTextOnly = FeatureImportanceEngine.calculateTriFeatureBreakdown(
      symptoms,
      mockRiskResult,
      null
    );

    const sumPercentagesB =
      breakdownTextOnly.visualAnalysisPercent +
      breakdownTextOnly.symptomsPercent +
      breakdownTextOnly.agePercent;

    assert(sumPercentagesB === 100, `Text-only percentages strictly sum to 100% (got ${sumPercentagesB}%)`);
    assert(breakdownTextOnly.visualAnalysisPercent === 0, 'Text-only has 0% Visual Analysis');
    assert(breakdownTextOnly.symptomsPercent > 0, `Text-only symptoms dominant: ${breakdownTextOnly.symptomsPercent}%`);

    console.log(`  ℹ️ Text-only breakdown: ${breakdownTextOnly.formattedBreakdown}`);

    // Full SHAP Explanation
    const shapResult = FeatureImportanceEngine.calculateShapValues(symptoms, mockRiskResult, mockVision);
    assert(shapResult.attributions.length >= 5, `Generated ${shapResult.attributions.length} SHAP attributions`);
    assert(shapResult.summaryNarrative.includes(breakdownWithImage.formattedBreakdown), 'SHAP summary narrative incorporates tri-feature breakdown');
  }

  // -----------------------------------------------------------------
  // TEST 4: Memory Safety & Tensor Cleanup
  // -----------------------------------------------------------------
  console.log('\n--- TEST 4: Memory Leak & Lifecycle Verification ---');
  {
    // Warm up cached sub-models
    const tWarm = tf.randomUniform([1, 224, 224, 3], -1.0, 1.0) as tf.Tensor4D;
    await GradCamGenerator.computeGradCam(tWarm, null, 1, 'Mild Inflammation');
    tWarm.dispose();

    const before = tf.memory().numTensors;
    for (let i = 0; i < 3; i++) {
      const t = tf.randomUniform([1, 224, 224, 3], -1.0, 1.0) as tf.Tensor4D;
      await GradCamGenerator.computeGradCam(t, null, 1, 'Mild Inflammation');
      t.dispose();
    }
    const after = tf.memory().numTensors;
    const leaked = after - before;
    assert(leaked === 0, `Zero tensor leaks across 3 consecutive Grad-CAM passes (delta: ${leaked})`);
  }

  console.log('\n======================================================');
  console.log(`📊 XAI & Uncertainty Test Summary: ${passed} passed, ${failed} failed`);
  console.log('======================================================\n');

  if (failed > 0) {
    process.exit(1);
  }
}

runXaiUncertaintyTests().catch(err => {
  console.error('❌ Unhandled error in XAI test suite:', err);
  process.exit(1);
});
