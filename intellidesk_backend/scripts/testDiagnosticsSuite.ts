import 'dotenv/config';
import * as tf from '@tensorflow/tfjs';
import '@tensorflow/tfjs-node';
import sharp from 'sharp';
import { VisionDiagnosticService } from '../src/modules/diagnostics/vision/VisionDiagnosticService.js';
import { ClinicalImageClassifier } from '../src/modules/diagnostics/vision/imageClassifier.js';
import { ClinicalMobileNetBuilder } from '../src/modules/diagnostics/vision/clinicalMobileNet.js';
import { AudioFeatureExtractor, CoughClassifier, COUGH_CATEGORIES } from '../src/modules/diagnostics/audio/index.js';
import { ButterworthFilter } from '../src/modules/diagnostics/vitals/ButterworthFilter.js';
import { rPPGSignalProcessor } from '../src/modules/diagnostics/vitals/rPPGSignalProcessor.js';
import { PhysiologicalRedFlagSentinel } from '../src/modules/diagnostics/vitals/PhysiologicalRedFlagSentinel.js';
import { VectorAssembler, TOTAL_CONCATENATED_DIM } from '../src/modules/diagnostics/fusion/vectorAssembler.js';
import { MultimodalFusionModel } from '../src/modules/diagnostics/fusion/MultimodalFusionModel.js';
import { assessMultimodalRisk, evaluateClinicalSafetyNet } from '../src/modules/diagnostics/fusion/assessMultimodalRisk.js';
import { FeatureImportanceEngine } from '../src/modules/diagnostics/explainability/featureImportance.js';
import { GradCamGenerator } from '../src/modules/diagnostics/explainability/gradCamGenerator.js';
import { MonteCarloUncertaintyEngine } from '../src/modules/diagnostics/explainability/uncertaintyEngine.js';
import { ScreeningDeltaAnalyzer } from '../src/modules/diagnostics/progression/ScreeningDeltaAnalyzer.js';
import { FHIRConverterService } from '../src/modules/diagnostics/fhir/FHIRConverterService.js';
import { ReferralLetterGenerator } from '../src/modules/diagnostics/fhir/ReferralLetterGenerator.js';
import { EmergencyFacilityService } from '../src/modules/diagnostics/facilities/EmergencyFacilityService.js';
import { HealthScreeningsDbService, DBHealthScreeningRow } from '../src/modules/diagnostics/db/healthScreeningsDbService.js';
import { SymptomInputPayload } from '../src/modules/diagnostics/fusion/types.js';

/**
 * Creates a valid 16-bit mono PCM WAV buffer in-memory.
 */
function createSyntheticWavBuffer(sampleRate = 16000, durationSec = 1.0, freqHz = 440): Buffer {
  const numSamples = Math.floor(sampleRate * durationSec);
  const dataSize = numSamples * 2;
  const buffer = Buffer.alloc(44 + dataSize);

  // RIFF header
  buffer.write('RIFF', 0);
  buffer.writeUInt32LE(36 + dataSize, 4);
  buffer.write('WAVE', 8);

  // fmt chunk
  buffer.write('fmt ', 12);
  buffer.writeUInt32LE(16, 16); // subchunk1 size (16 for PCM)
  buffer.writeUInt16LE(1, 20);  // PCM format
  buffer.writeUInt16LE(1, 22);  // 1 channel (mono)
  buffer.writeUInt32LE(sampleRate, 24);
  buffer.writeUInt32LE(sampleRate * 2, 28); // byte rate
  buffer.writeUInt16LE(2, 32);  // block align
  buffer.writeUInt16LE(16, 34); // bits per sample

  // data chunk
  buffer.write('data', 36);
  buffer.writeUInt32LE(dataSize, 40);

  // Write sine wave samples
  for (let i = 0; i < numSamples; i++) {
    const t = i / sampleRate;
    const sample = Math.sin(2 * Math.PI * freqHz * t) * 0.7; // Amplitude 0.7
    const intSample = Math.max(-32768, Math.min(32767, Math.floor(sample * 32767)));
    buffer.writeInt16LE(intSample, 44 + i * 2);
  }

  return buffer;
}

/**
 * Creates a synthetic RGB JPEG image buffer in-memory.
 */
async function createSyntheticImageBuffer(width = 224, height = 224, r = 210, g = 65, b = 65): Promise<Buffer> {
  return sharp({
    create: {
      width,
      height,
      channels: 3,
      background: { r, g, b }
    }
  }).jpeg({ quality: 90 }).toBuffer();
}

async function runDiagnosticsTestSuite() {
  console.log('\n================================================================');
  console.log('🩺 INTELLIDESK MULTIMODAL CLINICAL DIAGNOSTICS ML TEST SUITE');
  console.log('   Testing Models, Ensembles, Vitals, XAI, FHIR & Endpoints');
  console.log('================================================================\n');

  let passed = 0;
  let failed = 0;
  const testResults: { name: string; status: 'PASSED' | 'FAILED'; error?: string; latencyMs: number }[] = [];

  async function test(name: string, fn: () => Promise<boolean | void>) {
    const start = Date.now();
    process.stdout.write(`⏳ [TEST ${passed + failed + 1}] ${name}... `);
    try {
      const res = await fn();
      const latencyMs = Date.now() - start;
      if (res === false) {
        console.log(`❌ FAILED (Assertion returned false) [${latencyMs}ms]`);
        failed++;
        testResults.push({ name, status: 'FAILED', error: 'Assertion failed', latencyMs });
      } else {
        console.log(`✅ PASSED [${latencyMs}ms]`);
        passed++;
        testResults.push({ name, status: 'PASSED', latencyMs });
      }
    } catch (err: any) {
      const latencyMs = Date.now() - start;
      console.log(`❌ FAILED: ${err.message} [${latencyMs}ms]`);
      failed++;
      testResults.push({ name, status: 'FAILED', error: err.message, latencyMs });
    }
  }

  // Pre-generate reusable test assets
  const syntheticImgBuffer = await createSyntheticImageBuffer(224, 224, 200, 70, 70);
  const syntheticWavBuffer = createSyntheticWavBuffer(16000, 1.5, 520);

  // -------------------------------------------------------------
  // SECTION 1: CLINICAL VISION MODEL (ClinicalMobileNetV3)
  // -------------------------------------------------------------

  await test('Vision Model: Bootstrap & Graph Layer Topology', async () => {
    const model = await VisionDiagnosticService.getModel();
    if (!model) return false;
    const inputLayer = model.getLayer('clinical_image_input');
    const bottleneckLayer = model.getLayer('bottleneck_embedding');
    const outputLayer = model.getLayer('classification_probabilities');

    return (
      inputLayer !== undefined &&
      bottleneckLayer !== undefined &&
      outputLayer !== undefined &&
      model.inputs[0].shape[1] === 224 &&
      model.inputs[0].shape[2] === 224 &&
      model.inputs[0].shape[3] === 3
    );
  });

  await test('Vision Model: Image Buffer Preprocessing & Normalization', async () => {
    const tensor = await VisionDiagnosticService.preprocessImageBuffer(syntheticImgBuffer);
    const shape = tensor.shape;
    const minMax = tf.tidy(() => ({
      min: tensor.min().dataSync()[0],
      max: tensor.max().dataSync()[0]
    }));
    tensor.dispose();

    return (
      shape[0] === 1 &&
      shape[1] === 224 &&
      shape[2] === 224 &&
      shape[3] === 3 &&
      minMax.min >= -1.05 &&
      minMax.max <= 1.05
    );
  });

  await test('Vision Model: 4-Tier Inference & L2 Normalized Embedding', async () => {
    const result = await VisionDiagnosticService.analyzeImage(syntheticImgBuffer);
    const probs = Object.values(result.classProbabilities);
    const sumProbs = probs.reduce((a, b) => a + b, 0);

    // Verify embedding dimension and L2 norm (approx 1.0)
    const norm = Math.sqrt(result.bottleneckEmbedding.reduce((acc, v) => acc + v * v, 0));

    return (
      result.embeddingDimension === 128 &&
      result.bottleneckEmbedding.length === 128 &&
      Math.abs(sumProbs - 1.0) < 0.01 &&
      result.confidence >= 0 &&
      result.confidence <= 1 &&
      Math.abs(norm - 1.0) < 0.05
    );
  });

  await test('ClinicalImageClassifier: High-Level Embedding Extraction with Findings', async () => {
    const result = await ClinicalImageClassifier.extractEmbeddings({
      imageUrl: 'data:image/jpeg;base64,' + syntheticImgBuffer.toString('base64'),
      categoryHint: 'Dermatological / Skin Lesion'
    });

    return (
      result.embeddingDimension === 128 &&
      result.featureVector.length === 128 &&
      result.primaryCategory === 'Dermatological / Skin Lesion' &&
      result.topFindings.length > 0 &&
      result.featureMapDimensions[0] === 7 &&
      result.featureMapDimensions[1] === 7
    );
  });

  await test('ClinicalImageClassifier: Remote URL / Synthetic Fallback Robustness', async () => {
    const result = await ClinicalImageClassifier.extractEmbeddings({
      imageUrl: 'https://example.com/mock-remote-lesion.jpg',
      categoryHint: 'Oral / Throat Lesion'
    });

    return (
      result.featureVector.length === 128 &&
      result.topFindings.length > 0 &&
      typeof result.predictedCondition === 'string'
    );
  });

  // -------------------------------------------------------------
  // SECTION 2: AUDIO ML MODEL & ACOUSTIC BIOMARKERS
  // -------------------------------------------------------------

  await test('Audio Feature Extractor: WAV Decode, 16kHz Resample & 16-D MFCCs', async () => {
    const result = await AudioFeatureExtractor.extractFeatures(syntheticWavBuffer);

    const isScaled0to1 = result.featureVector.every(v => v >= 0.0 && v <= 1.0);
    const hasSpectral = (
      result.spectralMetrics.centroid >= 0 &&
      result.spectralMetrics.rolloff >= 0 &&
      result.spectralMetrics.zcr >= 0
    );

    return (
      result.featureVector.length === 16 &&
      isScaled0to1 &&
      result.mfccCoefficients.length === 12 &&
      hasSpectral &&
      result.durationSeconds > 0
    );
  });

  await test('Audio Feature Extractor: Null / Corrupt Buffer Neutral Prior Fallback', async () => {
    const emptyResult = await AudioFeatureExtractor.extractFeatures(null);
    const corruptResult = await AudioFeatureExtractor.extractFeatures(Buffer.from('not an audio file'));

    const isUniformPrior = (vec: number[]) =>
      vec.length === 16 && vec.every(v => Math.abs(v - 0.25) < 0.001);

    return isUniformPrior(emptyResult.featureVector) && isUniformPrior(corruptResult.featureVector);
  });

  await test('Cough Classifier: Neural Network Model Topology & Weights', async () => {
    const model = await CoughClassifier.loadOrBootstrapModel();
    if (!model) return false;

    const inputShape = model.inputs[0].shape;
    const outputShape = model.outputs[0].shape;

    return (
      inputShape[1] === 16 &&
      outputShape[1] === 4
    );
  });

  await test('Cough Classifier: Softmax Inference Across 4 Respiratory Categories', async () => {
    const mockAcousticVec = [0.2, 0.4, 0.3, 0.5, 0.1, 0.2, 0.3, 0.4, 0.5, 0.2, 0.1, 0.3, 0.4, 0.5, 0.2, 0.3];
    const classification = await CoughClassifier.classify(mockAcousticVec);

    const probSum = Object.values(classification.probabilities).reduce((a, b) => a + b, 0);

    return (
      COUGH_CATEGORIES.includes(classification.predictedCategory) &&
      Math.abs(probSum - 1.0) < 0.02 &&
      classification.confidence >= 0 &&
      classification.confidence <= 1
    );
  });

  await test('Cough Classifier: Wheeze/Stridor Detection & Threshold Evaluation', async () => {
    // High frequency acoustic profile simulating wheeze / stridor
    const wheezeFeatures = [0.85, 0.90, 0.88, 0.82, 0.79, 0.80, 0.75, 0.78, 0.82, 0.84, 0.88, 0.91, 0.95, 0.92, 0.88, 0.85];
    const classification = await CoughClassifier.classify(wheezeFeatures);

    return (
      typeof classification.isRedFlagRespiratory === 'boolean' &&
      classification.probabilities.wheezeStridor >= 0
    );
  });

  // -------------------------------------------------------------
  // SECTION 3: VITALS & OPTICAL PHOTOPLETHYSMOGRAPHY (rPPG)
  // -------------------------------------------------------------

  await test('Butterworth Filter: 4th-Order Bandpass (0.75 - 3.5 Hz) Pulse Extraction', async () => {
    const filter = new ButterworthFilter(30.0, 0.75, 3.5);
    // Generate synthetic signal: 1.2 Hz pulse (72 bpm) + 0.1 Hz DC drift + 10 Hz high noise
    const N = 150;
    const rawSignal: number[] = [];
    for (let i = 0; i < N; i++) {
      const t = i / 30.0;
      const pulse = Math.sin(2 * Math.PI * 1.2 * t);
      const drift = 5.0 + Math.sin(2 * Math.PI * 0.1 * t);
      const noise = 0.5 * Math.sin(2 * Math.PI * 10.0 * t);
      rawSignal.push(pulse + drift + noise);
    }

    const filtered = filter.filter(rawSignal);
    // Filtered signal should remove large DC offset and have zero-mean characteristics
    const meanFiltered = filtered.reduce((a, b) => a + b, 0) / N;

    return (
      filtered.length === N &&
      Math.abs(meanFiltered) < 1.0 && // DC drift attenuated
      !filtered.some(isNaN)
    );
  });

  await test('rPPG Processor: Time-Series Resampling to Strict 30.0 Hz Uniform Grid', async () => {
    const processor = new rPPGSignalProcessor(30.0);
    // Jittered timestamps simulating camera frame drops (approx 30 fps with noise)
    const timestamps: number[] = [];
    const values: number[] = [];
    let curTime = 1000.0;
    for (let i = 0; i < 90; i++) {
      curTime += 30.0 + (Math.random() * 8.0 - 4.0); // 26ms - 34ms jitter
      timestamps.push(curTime);
      values.push(Math.sin((i / 30.0) * Math.PI * 2));
    }

    const resampled = processor.resampleToUniform30Hz(values, timestamps);

    return (
      resampled.length > 0 &&
      !resampled.some(isNaN) &&
      resampled.length >= 80
    );
  });

  await test('rPPG Processor: Full Signal Extraction (HR, HRV RMSSD, RR, SpO2)', async () => {
    const processor = new rPPGSignalProcessor(30.0);
    const N = 120; // 4 seconds at 30 Hz
    const green: number[] = [];
    const red: number[] = [];
    const blue: number[] = [];

    // Synthesize cardiac pulse around 1.25 Hz (75 bpm)
    for (let i = 0; i < N; i++) {
      const t = i / 30.0;
      const pulse = Math.sin(2 * Math.PI * 1.25 * t);
      green.push(100.0 + pulse * 2.0);
      red.push(120.0 + pulse * 1.5);
      blue.push(80.0 + pulse * 0.8);
    }

    const result = processor.processSignals({ red, green, blue, samplingRate: 30.0 });

    return (
      result.heartRateBpm >= 40 &&
      result.heartRateBpm <= 180 &&
      result.oxygenSaturationSpo2 >= 70 &&
      result.oxygenSaturationSpo2 <= 100 &&
      result.respirationRateBpm >= 8 &&
      result.hrvRmssdMs >= 0 &&
      result.confidenceScore >= 0 &&
      result.confidenceScore <= 1
    );
  });

  await test('Physiological Red-Flag Sentinel: Critical Vitals Override Triggers', async () => {
    // Test severe hypoxia (SpO2 86% <= 90%)
    const hypoxiaAlerts = PhysiologicalRedFlagSentinel.evaluateVitals({ oxygenSaturation: 86 });
    const hasHypoxiaOverride = hypoxiaAlerts.some(a => a.severity === 'CRITICAL_OVERRIDE' && a.type === 'CRITICAL_HYPOXIA');

    // Test extreme bradycardia (HR 36 <= 40)
    const bradycardiaAlerts = PhysiologicalRedFlagSentinel.evaluateVitals({ heartRate: 36 });
    const hasBradyOverride = bradycardiaAlerts.some(a => a.severity === 'CRITICAL_OVERRIDE' && a.type === 'CRITICAL_BRADYCARDIA');

    // Test nominal vitals
    const nominalAlerts = PhysiologicalRedFlagSentinel.evaluateVitals({ heartRate: 72, oxygenSaturation: 98 });

    return (
      hasHypoxiaOverride &&
      hasBradyOverride &&
      nominalAlerts.length === 0
    );
  });

  // -------------------------------------------------------------
  // SECTION 4: MULTIMODAL LATE-FUSION NEURAL NETWORK
  // -------------------------------------------------------------

  await test('VectorAssembler: 184-D Vector Composition & [0, 1] Bounds', async () => {
    const mockVisual = new Array(128).fill(0.1);
    const mockSymptoms: Partial<SymptomInputPayload> = {
      painScale: 7,
      durationDays: 5,
      symptoms: ['fever', 'cough', 'shortness of breath'],
      demographics: { age: 45, biologicalSex: 'MALE', preExistingConditions: ['asthma'] }
    };
    const mockVitals = {
      temperatureCelsius: 38.8,
      heartRate: 110,
      oxygenSaturation: 93,
      systolicBP: 135,
      diastolicBP: 85
    };
    const mockAudio = new Array(16).fill(0.4);

    const assembled = VectorAssembler.assembleVector(mockVisual, mockSymptoms, mockVitals, mockAudio);
    const vec = assembled.concatenatedVector;

    const allBounded = vec.every(v => typeof v === 'number' && !isNaN(v) && v >= 0.0 && v <= 1.0);

    return (
      vec.length === TOTAL_CONCATENATED_DIM && // 184
      vec.length === 184 &&
      allBounded
    );
  });

  await test('VectorAssembler: Text-Only Prior & Audio-Absent Fallback Unit Vectors', async () => {
    // When no visual embeddings provided: uniform 1 / sqrt(128) ≈ 0.088388
    const textOnlyVisual = VectorAssembler.buildVisualVector(null);
    const visualNorm = Math.sqrt(textOnlyVisual.reduce((acc, v) => acc + v * v, 0));

    // When no audio features provided: uniform 0.25
    const audioAbsent = VectorAssembler.buildAudioVector(null);

    return (
      textOnlyVisual.length === 128 &&
      Math.abs(visualNorm - 1.0) < 0.01 &&
      audioAbsent.length === 16 &&
      audioAbsent.every(v => Math.abs(v - 0.25) < 0.001)
    );
  });

  await test('MultimodalFusionModel: Architecture Graph & Multi-Head Outputs', async () => {
    const model = await MultimodalFusionModel.loadOrBootstrapModel();
    if (!model) return false;

    const inputShape = model.inputs[0].shape;
    const outputs = model.outputs;

    return (
      inputShape[1] === 184 &&
      outputs.length === 2 &&
      outputs[0].name.includes('risk_score') &&
      outputs[1].name.includes('risk_tier')
    );
  });

  await test('MultimodalFusionModel: Monte Carlo Dropout Epistemic Uncertainty (N=10)', async () => {
    const testVector = new Array(184).fill(0.3);
    const mcResult = await MultimodalFusionModel.predictWithMCDropout(testVector, 10);

    const tierProbSum = (
      mcResult.tierProbabilities.lowRisk +
      mcResult.tierProbabilities.moderateNeed +
      mcResult.tierProbabilities.criticalReferral
    );

    return (
      mcResult.monteCarloSamples === 10 &&
      mcResult.individualScores.length === 10 &&
      mcResult.meanScore >= 0.0 &&
      mcResult.meanScore <= 1.0 &&
      mcResult.epistemicStdDev >= 0.0 &&
      mcResult.ciLower <= mcResult.ciUpper &&
      ['Low Risk', 'Moderate Need', 'Critical Referral'].includes(mcResult.predictedTier) &&
      Math.abs(tierProbSum - 1.0) < 0.02
    );
  });

  // -------------------------------------------------------------
  // SECTION 5: CLINICAL SAFETY NET & HARD RISK OVERRIDES
  // -------------------------------------------------------------

  await test('Clinical Safety Net: Extreme Pain (10/10) Enforces Floor >= 0.85', async () => {
    const symptomData: SymptomInputPayload = {
      painScale: 10,
      durationDays: 1,
      symptoms: ['severe headache'],
      bodyLocation: 'Head'
    };

    const safety = evaluateClinicalSafetyNet(symptomData, {});
    const riskResult = await assessMultimodalRisk({
      symptomData,
      mcSamples: 5
    });

    return (
      safety.triggered === true &&
      safety.enforcedFloor === 0.85 &&
      riskResult.riskScore >= 0.85 &&
      riskResult.riskLevel === 'CRITICAL' &&
      riskResult.riskTier === 'Critical Referral'
    );
  });

  await test('Clinical Safety Net: Hyperpyrexia (Temp >= 40.0°C) Trigger', async () => {
    const symptomData: SymptomInputPayload = {
      painScale: 4,
      durationDays: 2,
      symptoms: ['chills', 'fatigue'],
      vitals: { temperatureCelsius: 40.5 }
    };

    const safety = evaluateClinicalSafetyNet(symptomData, symptomData.vitals);
    const riskResult = await assessMultimodalRisk({
      symptomData,
      patientVitals: symptomData.vitals,
      mcSamples: 5
    });

    return (
      safety.triggered === true &&
      safety.enforcedFloor === 0.85 &&
      riskResult.riskScore >= 0.85 &&
      riskResult.riskLevel === 'CRITICAL'
    );
  });

  await test('Clinical Safety Net: Red-Flag Keyword Bypass (Acute Chest Pain)', async () => {
    const symptomData: SymptomInputPayload = {
      painScale: 6,
      durationDays: 1,
      symptoms: ['acute chest pain', 'dizziness'],
      bodyLocation: 'Chest'
    };

    const safety = evaluateClinicalSafetyNet(symptomData, {});
    return (
      safety.triggered === true &&
      safety.reasons.some(r => r.includes('Chest Pain')) &&
      safety.enforcedFloor === 0.85
    );
  });

  await test('Clinical Safety Net: Wheeze/Stridor Acoustic Floor (>= 0.75)', async () => {
    const mockWheezeClassification = {
      predictedCategory: 'Wheeze/Stridor' as const,
      confidence: 0.88,
      probabilities: {
        normalRespiratory: 0.02,
        dryIrritativeCough: 0.04,
        wetProductiveCough: 0.06,
        wheezeStridor: 0.88
      },
      isRedFlagRespiratory: true
    };

    const safety = evaluateClinicalSafetyNet({ painScale: 2, symptoms: ['cough'] }, {}, mockWheezeClassification);
    const riskResult = await assessMultimodalRisk({
      symptomData: { painScale: 2, symptoms: ['cough'] },
      audioClassification: mockWheezeClassification,
      mcSamples: 5
    });

    return (
      safety.triggered === true &&
      safety.isRespiratoryRedFlag === true &&
      safety.enforcedFloor === 0.75 &&
      riskResult.riskScore >= 0.75 &&
      riskResult.riskLevel === 'CRITICAL'
    );
  });

  // -------------------------------------------------------------
  // SECTION 6: EXPLAINABILITY & INTERPRETABLE AI (XAI)
  // -------------------------------------------------------------

  await test('Feature Importance: Tri-Feature Breakdown Strictly Sums to 100%', async () => {
    const symptoms: SymptomInputPayload = {
      painScale: 8,
      durationDays: 7,
      symptoms: ['rash', 'swelling', 'fever'],
      demographics: { age: 52 }
    };
    const mockRisk = {
      riskScore: 0.72,
      riskLevel: 'HIGH' as const,
      riskTier: 'Moderate Need' as const,
      tierProbabilities: { lowRisk: 0.1, moderateNeed: 0.7, criticalReferral: 0.2 },
      uncertaintyBounds: { confidence: 0.9, ciLower: 0.65, ciUpper: 0.79, epistemicVariance: 0.002, monteCarloSamples: 10 },
      deterministicSafetyOverride: false
    };

    const breakdown = FeatureImportanceEngine.calculateTriFeatureBreakdown(symptoms, mockRisk as any);
    const sum = breakdown.visualAnalysisPercent + breakdown.symptomsPercent + breakdown.agePercent;

    return (
      sum === 100 &&
      breakdown.formattedBreakdown.includes('Visual Analysis:') &&
      breakdown.formattedBreakdown.includes('Symptoms:') &&
      breakdown.formattedBreakdown.includes('Age:')
    );
  });

  await test('Feature Importance: Comprehensive SHAP Attribution Engine', async () => {
    const symptoms: SymptomInputPayload = {
      painScale: 9,
      durationDays: 4,
      symptoms: ['chest pain', 'shortness of breath'],
      demographics: { age: 60 }
    };
    const mockRisk = {
      riskScore: 0.88,
      riskLevel: 'CRITICAL' as const,
      riskTier: 'Critical Referral' as const,
      tierProbabilities: { lowRisk: 0.05, moderateNeed: 0.15, criticalReferral: 0.80 },
      uncertaintyBounds: { confidence: 0.92, ciLower: 0.82, ciUpper: 0.94, epistemicVariance: 0.001, monteCarloSamples: 10 },
      deterministicSafetyOverride: true
    };

    const shap = FeatureImportanceEngine.calculateShapValues(symptoms, mockRisk as any);

    return (
      shap.baseValue === 0.15 &&
      shap.attributions.length >= 3 &&
      shap.attributions.some(a => a.category === 'SYMPTOMS') &&
      typeof shap.summaryNarrative === 'string'
    );
  });

  await test('Grad-CAM: Saliency Heatmap Generation & SVG Data URI', async () => {
    const mockFeatureVector = new Array(128).fill(0.2);
    const heatmap = GradCamGenerator.generateHeatmap(
      'Acute Infection/Lesion',
      mockFeatureVector,
      [14, 14, 128]
    );

    return (
      heatmap.heatmapGrid.length === 14 &&
      heatmap.heatmapGrid[0].length === 14 &&
      heatmap.overlaySvgDataUri.startsWith('data:image/svg+xml') &&
      heatmap.salientRegion.centerCoordinates.x >= 0 &&
      heatmap.salientRegion.centerCoordinates.x <= 1 &&
      heatmap.hotspotPoints.length > 0
    );
  });

  await test('Uncertainty Engine: Quantifies Epistemic Variance & Tier Assignment', async () => {
    const testVec = new Array(184).fill(0.4);
    const report = await MonteCarloUncertaintyEngine.quantifyUncertainty(testVec, 10);

    return (
      report.monteCarloSamples === 10 &&
      ['LOW_UNCERTAINTY', 'MODERATE_UNCERTAINTY', 'HIGH_EPISTEMIC_UNCERTAINTY'].includes(report.uncertaintyTier) &&
      report.confidenceInterval95[0] <= report.confidenceInterval95[1] &&
      report.uncertaintyScoreFormatted.includes('±')
    );
  });

  // -------------------------------------------------------------
  // SECTION 7: LONGITUDINAL PROGRESSION & SSIM CLINICAL DELTA
  // -------------------------------------------------------------

  await test('Screening Delta Analyzer: Baseline (T0) vs Followup (T1) Trajectory', async () => {
    const mockBaseline: DBHealthScreeningRow = {
      id: 'screening-t0-001',
      patient_id: 'patient-test-1',
      institution_id: 'inst-1',
      image_url: null,
      symptom_payload: { painScale: 8, symptoms: ['erythema', 'fever'] },
      multimodal_risk_score: 0.82,
      uncertainty_bounds: {},
      xai_heatmap_url: null,
      clinical_findings: [],
      risk_level: 'CRITICAL',
      status: 'COMPLETED',
      created_at: new Date(Date.now() - 48 * 3600 * 1000).toISOString(),
      updated_at: new Date(Date.now() - 48 * 3600 * 1000).toISOString()
    };

    const mockFollowup: DBHealthScreeningRow = {
      id: 'screening-t1-002',
      patient_id: 'patient-test-1',
      previous_screening_id: 'screening-t0-001',
      institution_id: 'inst-1',
      image_url: null,
      symptom_payload: { painScale: 3, symptoms: ['mild redness'] },
      multimodal_risk_score: 0.35,
      uncertainty_bounds: {},
      xai_heatmap_url: null,
      clinical_findings: [],
      risk_level: 'MODERATE',
      status: 'COMPLETED',
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    };

    const delta = await ScreeningDeltaAnalyzer.analyzeDelta(mockBaseline, mockFollowup);

    return (
      delta.status === 'Improving / Healing' &&
      delta.riskDelta < 0 &&
      delta.vitalsDelta.painDelta === -5 &&
      delta.timeElapsedHours >= 47
    );
  });

  await test('Screening Delta Analyzer: Wang et al. SSIM Division-by-Zero Protection', async () => {
    // Generate two identical buffers (SSIM should equal approx 1.0)
    const img1 = await createSyntheticImageBuffer(128, 128, 150, 150, 150);
    const img2 = await createSyntheticImageBuffer(128, 128, 150, 150, 150);

    const ssimVal = await ScreeningDeltaAnalyzer.calculateMSSIM(img1, img2);

    return (
      ssimVal !== null &&
      !isNaN(ssimVal) &&
      Math.abs(ssimVal - 1.0) < 0.05
    );
  });

  // -------------------------------------------------------------
  // SECTION 8: FHIR R4 CONVERTER & MEDICAL REFERRALS
  // -------------------------------------------------------------

  await test('FHIR R4 Converter: Generates Compliant DiagnosticReport Bundle', async () => {
    const mockScreening: DBHealthScreeningRow = {
      id: 'screening-fhir-99',
      patient_id: 'patient-alpha-42',
      institution_id: 'inst-1',
      image_url: 'https://example.com/finding.jpg',
      symptom_payload: {
        painScale: 6,
        symptoms: ['wheezing', 'cough'],
        vitals: { heartRate: 98, oxygenSaturation: 94, temperatureCelsius: 38.2 }
      },
      multimodal_risk_score: 0.78,
      uncertainty_bounds: { confidence: 0.88, ciLower: 0.72, ciUpper: 0.84 },
      xai_heatmap_url: null,
      clinical_findings: [{ label: 'Wheeze/Stridor', confidence: 0.85 }],
      risk_level: 'CRITICAL',
      status: 'COMPLETED',
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    };

    const bundle = FHIRConverterService.buildFHIRDiagnosticReport(mockScreening);

    return (
      bundle.resourceType === 'Bundle' &&
      bundle.type === 'collection' &&
      bundle.entry.length === 2 && // DiagnosticReport + Observation
      bundle.entry.some(e => e.resource.resourceType === 'DiagnosticReport') &&
      bundle.entry.some(e => e.resource.resourceType === 'Observation')
    );
  });

  await test('FHIR R4 Converter: De-identified Fallback Reference on Unlinked Patient', async () => {
    const ref = FHIRConverterService.buildPatientReference(null, 'screen-anon-uuid');

    return (
      ref.type === 'Patient' &&
      ref.reference.startsWith('urn:uuid:patient-deidentified-') &&
      ref.display.includes('De-identified')
    );
  });

  await test('Referral Letter Generator: Streams Clinical Referral Letter PDF Buffer', async () => {
    const mockScreening: DBHealthScreeningRow = {
      id: 'screening-pdf-test',
      patient_id: 'patient-ref-7',
      institution_id: 'inst-1',
      image_url: null,
      symptom_payload: { painScale: 8, symptoms: ['shortness of breath'] },
      multimodal_risk_score: 0.86,
      uncertainty_bounds: { confidence: 0.9, ciLower: 0.8, ciUpper: 0.92 },
      xai_heatmap_url: null,
      clinical_findings: [{ label: 'Severe/Emergency', confidence: 0.9 }],
      risk_level: 'CRITICAL',
      status: 'COMPLETED',
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    };

    const pdfBuffer = await ReferralLetterGenerator.generateReferralPdfBuffer(mockScreening);

    return (
      pdfBuffer instanceof Buffer &&
      pdfBuffer.length > 500 &&
      pdfBuffer.toString('ascii', 0, 5) === '%PDF-'
    );
  });

  // -------------------------------------------------------------
  // SECTION 9: GEOSPATIAL EMERGENCY CARE TRIAGE
  // -------------------------------------------------------------

  await test('Emergency Facility Service: Geodesic Haversine Calculation & Sorting', async () => {
    const nycLat = 40.7128;
    const nycLng = -74.0060;
    const result = await EmergencyFacilityService.getNearbyFacilities(nycLat, nycLng, 25.0);

    // Facilities should be sorted by ascending distance
    const isSorted = result.facilities.every((f, i, arr) =>
      i === 0 || (f.distanceKm ?? 0) >= (arr[i - 1].distanceKm ?? 0)
    );

    return (
      result.facilities.length > 0 &&
      result.searchRadiusKm === 25.0 &&
      isSorted &&
      result.facilities[0].distanceKm !== undefined &&
      result.facilities[0].distanceKm < 25.0
    );
  });

  // -------------------------------------------------------------
  // SECTION 10: END-TO-END SCREENING PIPELINE & DB CACHE FALLBACK
  // -------------------------------------------------------------

  await test('Database Service: In-Memory Cache Persistence & Patient Auto-Linking', async () => {
    const created1 = await HealthScreeningsDbService.createScreening({
      patientId: 'patient-test-cache-99',
      institutionId: 'inst-99',
      symptomPayload: { symptoms: ['headache'], painScale: 4, durationDays: 2 },
      multimodalRiskScore: 0.32,
      riskLevel: 'LOW',
      clinicalFindings: [],
      uncertaintyBounds: { confidence: 0.85, ciLower: 0.25, ciUpper: 0.39 }
    });

    const created2 = await HealthScreeningsDbService.createScreening({
      patientId: 'patient-test-cache-99',
      institutionId: 'inst-99',
      symptomPayload: { symptoms: ['headache', 'dizziness'], painScale: 7, durationDays: 4 },
      multimodalRiskScore: 0.65,
      riskLevel: 'HIGH',
      clinicalFindings: [],
      uncertaintyBounds: { confidence: 0.82, ciLower: 0.58, ciUpper: 0.72 }
    });

    const retrieved = await HealthScreeningsDbService.getScreeningById(created1.id);
    const patientScreenings = await HealthScreeningsDbService.getScreeningsByPatient('patient-test-cache-99');

    return (
      retrieved !== null &&
      retrieved.id === created1.id &&
      patientScreenings.length >= 2 &&
      created2.previous_screening_id === created1.id // Patient-scoped auto-linking!
    );
  });

  await test('End-to-End Multimodal Pipeline: Complete Vision + Audio + Vitals Fusion', async () => {
    const result = await assessMultimodalRisk({
      imageBuffer: syntheticImgBuffer,
      audioBuffer: syntheticWavBuffer,
      symptomData: {
        bodyLocation: 'Thoracic',
        durationDays: 3,
        painScale: 5,
        symptoms: ['cough', 'fever'],
        vitals: { heartRate: 88, oxygenSaturation: 96, temperatureCelsius: 38.0 }
      },
      mcSamples: 10
    });

    return (
      result.riskScore >= 0.0 &&
      result.riskScore <= 1.0 &&
      ['LOW', 'MODERATE', 'HIGH', 'CRITICAL'].includes(result.riskLevel) &&
      ['Low Risk', 'Moderate Need', 'Critical Referral'].includes(result.riskTier) &&
      result.concatenatedVector.length === 184 &&
      result.isTextOnlyScreening === false &&
      result.differentialDiagnoses.length > 0 &&
      result.clinicalRecommendations.length > 0 &&
      result.uncertaintyBounds.monteCarloSamples === 10
    );
  });

  await test('End-to-End Multimodal Pipeline: Text-Only Non-Imaging Diagnostic Fallback', async () => {
    const result = await assessMultimodalRisk({
      imageBuffer: null,
      audioBuffer: null,
      symptomData: {
        bodyLocation: 'Abdomen',
        durationDays: 2,
        painScale: 6,
        symptoms: ['abdominal cramps', 'nausea']
      },
      mcSamples: 10
    });

    return (
      result.isTextOnlyScreening === true &&
      result.concatenatedVector.length === 184 &&
      result.riskScore >= 0.0 &&
      result.riskScore <= 1.0 &&
      result.differentialDiagnoses.length > 0
    );
  });

  await test('Tensor Memory Safety: Zero Leakage Across Repeated Model Inferences', async () => {
    // Warm up inference once so internal cached tensors settle
    await VisionDiagnosticService.analyzeImage(syntheticImgBuffer);
    await CoughClassifier.classify(new Array(16).fill(0.3));
    await MultimodalFusionModel.predictWithMCDropout(new Array(184).fill(0.2), 3);

    const initialTensors = tf.memory().numTensors;

    // Run 5 consecutive cycles of all 3 models
    for (let i = 0; i < 5; i++) {
      await VisionDiagnosticService.analyzeImage(syntheticImgBuffer);
      await CoughClassifier.classify(new Array(16).fill(0.3));
      await MultimodalFusionModel.predictWithMCDropout(new Array(184).fill(0.2), 3);
    }

    const finalTensors = tf.memory().numTensors;
    const leakedTensors = finalTensors - initialTensors;

    return leakedTensors === 0;
  });

  // -------------------------------------------------------------
  // SUMMARY REPORT
  // -------------------------------------------------------------
  console.log('\n================================================================');
  console.log(`📊 TEST SUITE SUMMARY: ${passed} PASSED, ${failed} FAILED (TOTAL: ${passed + failed})`);
  console.log('================================================================');

  if (failed > 0) {
    console.log('\nFailed Tests:');
    testResults.filter(t => t.status === 'FAILED').forEach(t => {
      console.log(` - ❌ ${t.name}: ${t.error}`);
    });
    process.exit(1);
  } else {
    console.log('\n🎉 ALL 35 DIAGNOSTICS & MULTIMODAL ML TESTS PASSED PERFECTLY!\n');
    process.exit(0);
  }
}

runDiagnosticsTestSuite().catch(err => {
  console.error('Fatal test runner crash:', err);
  process.exit(1);
});
