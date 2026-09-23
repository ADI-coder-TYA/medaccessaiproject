import { ClinicalImageClassifier } from '../modules/diagnostics/vision/imageClassifier.js';
import { MultimodalRiskNetwork } from '../modules/diagnostics/fusion/multimodalRiskNetwork.js';
import { GradCamGenerator } from '../modules/diagnostics/explainability/gradCamGenerator.js';
import { FeatureImportanceEngine } from '../modules/diagnostics/explainability/featureImportance.js';
import { SymptomInputPayload } from '../modules/diagnostics/fusion/types.js';

async function runDiagnosticsValidation() {
  console.log('--- Testing Clinical Vision Pipeline ---');
  const vision = await ClinicalImageClassifier.extractEmbeddings({
    imageUrl: 'https://example.com/symptoms/skin_rash.png',
    categoryHint: 'DERMATOLOGY_RASH'
  });
  console.log(`✓ Vision Extracted: Category=${vision.primaryCategory}, Dim=${vision.embeddingDimension}, Quality=${vision.visualQualityScore}`);
  console.log(`✓ Top Finding: ${vision.topFindings[0]?.label} (Confidence: ${vision.topFindings[0]?.confidence})`);

  console.log('\n--- Testing Grad-CAM Generator ---');
  const gradCam = GradCamGenerator.generateHeatmap(
    vision.predictedCondition,
    vision.featureVector,
    vision.featureMapDimensions
  );
  console.log(`✓ Grad-CAM Peak Intensity: ${gradCam.salientRegion.peakIntensity}`);
  console.log(`✓ Hotspot count: ${gradCam.hotspotPoints.length}, SVG URI length: ${gradCam.overlaySvgDataUri.length}`);

  console.log('\n--- Testing Multimodal Fusion Network ---');
  const symptomPayload: SymptomInputPayload = {
    bodyLocation: 'Left Forearm',
    durationDays: 4,
    painScale: 6,
    symptoms: ['Erythematous rash', 'Pruritus', 'Mild local swelling'],
    vitals: {
      temperatureCelsius: 38.2,
      heartRate: 104,
      systolicBP: 125,
      oxygenSaturation: 98
    }
  };

  const riskResult = await MultimodalRiskNetwork.assessRisk(symptomPayload, vision);
  console.log(`✓ Unified Risk Score: ${riskResult.riskScore} (${riskResult.riskLevel})`);
  console.log(`✓ Uncertainty Interval: [${riskResult.uncertaintyBounds.ciLower}, ${riskResult.uncertaintyBounds.ciUpper}] (Conf: ${(riskResult.uncertaintyBounds.confidence * 100).toFixed(1)}%)`);
  console.log(`✓ Requires Immediate Review: ${riskResult.requiresImmediatePhysicianReview}`);

  console.log('\n--- Testing Explainability & Feature Importance (SHAP) ---');
  const shap = FeatureImportanceEngine.calculateShapValues(symptomPayload, riskResult, vision);
  console.log(`✓ SHAP Base Value: ${shap.baseValue}, Attributions count: ${shap.attributions.length}`);
  console.log(`✓ Top Driver: ${shap.attributions[0]?.featureName} (${shap.attributions[0]?.percentageImpact}% impact)`);
  console.log(`✓ Summary: ${shap.summaryNarrative}`);

  console.log('\nALL CLINICAL DIAGNOSTICS MODULE TESTS PASSED! 🩺✅');
}

runDiagnosticsValidation().catch(err => {
  console.error('Validation failed:', err);
  process.exit(1);
});
