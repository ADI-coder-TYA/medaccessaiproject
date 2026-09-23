import sharp from 'sharp';
import { DBHealthScreeningRow, HealthScreeningsDbService } from '../modules/diagnostics/db/healthScreeningsDbService.js';
import { ScreeningDeltaAnalyzer } from '../modules/diagnostics/progression/ScreeningDeltaAnalyzer.js';

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

async function runLongitudinalTests() {
  console.log('\n================================================================');
  console.log('🧪 Starting Longitudinal Screening & Progression Test Suite');
  console.log('================================================================\n');

  HealthScreeningsDbService.clearLocalCache();

  // -------------------------------------------------------------
  // TEST 1: Patient-Scoped Auto-Linking (Technical Guardrail 1)
  // -------------------------------------------------------------
  console.log('--- TEST 1: Patient-Scoped Auto-Linking (Guardrail 1) ---');

  const patientAlpha = 'pt-alpha-101';
  const patientBeta = 'pt-beta-202';

  // First screening for Alpha (baseline)
  const scr1Alpha = await HealthScreeningsDbService.createScreening({
    patientId: patientAlpha,
    institutionId: 'inst-test',
    symptomPayload: { symptoms: ['Mild rash'], vitals: { pain_score: 3, temperature: 37.1 } },
    multimodalRiskScore: 0.35,
    uncertaintyBounds: { confidence: 0.92, ci_lower: 0.31, ci_upper: 0.39, epistemic_variance: 0.001 },
    riskLevel: 'LOW'
  });

  assert(scr1Alpha.previous_screening_id === null, 'First screening for patientAlpha defaults to null (baseline)');

  // Second screening for Alpha (follow-up) without explicit previousScreeningId
  const scr2Alpha = await HealthScreeningsDbService.createScreening({
    patientId: patientAlpha,
    institutionId: 'inst-test',
    symptomPayload: { symptoms: ['Spreading erythema', 'Moderate burning'], vitals: { pain_score: 6, temperature: 38.2 } },
    multimodalRiskScore: 0.72,
    uncertaintyBounds: { confidence: 0.88, ci_lower: 0.67, ci_upper: 0.77, epistemic_variance: 0.002 },
    riskLevel: 'HIGH'
  });

  assert(
    scr2Alpha.previous_screening_id === scr1Alpha.id,
    `Follow-up screening auto-linked to previous screening ${scr1Alpha.id}`
  );

  // Third screening for patientBeta (should not link to Alpha)
  const scr1Beta = await HealthScreeningsDbService.createScreening({
    patientId: patientBeta,
    institutionId: 'inst-test',
    symptomPayload: { symptoms: ['Dry cough'], vitals: { pain_score: 1, temperature: 36.8 } },
    multimodalRiskScore: 0.22,
    uncertaintyBounds: { confidence: 0.95, ci_lower: 0.20, ci_upper: 0.24, epistemic_variance: 0.0005 },
    riskLevel: 'LOW'
  });

  assert(
    scr1Beta.previous_screening_id === null,
    'First screening for patientBeta has null previous_screening_id (does not link to patientAlpha)'
  );

  // Fourth screening for Alpha with explicit previous override
  const explicitOverrideId = 'scr-custom-override-999';
  const scr3Alpha = await HealthScreeningsDbService.createScreening({
    patientId: patientAlpha,
    previousScreeningId: explicitOverrideId,
    institutionId: 'inst-test',
    symptomPayload: { symptoms: ['Resolved redness'], vitals: { pain_score: 1, temperature: 36.6 } },
    multimodalRiskScore: 0.18,
    uncertaintyBounds: { confidence: 0.96, ci_lower: 0.15, ci_upper: 0.21, epistemic_variance: 0.0004 },
    riskLevel: 'LOW'
  });

  assert(
    scr3Alpha.previous_screening_id === explicitOverrideId,
    'Explicit previousScreeningId takes precedence over auto-linking'
  );

  // -------------------------------------------------------------
  // TEST 2: Division-by-Zero SSIM Regularization (Guardrail 3)
  // -------------------------------------------------------------
  console.log('\n--- TEST 2: Division-by-Zero SSIM Regularization (Guardrail 3) ---');

  // Synthesize a structured test image buffer (mimicking a lesion on skin)
  const baseImg = await sharp({
    create: {
      width: 256,
      height: 256,
      channels: 3,
      background: { r: 220, g: 190, b: 170 } // skin tone
    }
  })
    .composite([
      {
        // Erythema / lesion hotspot in center
        input: Buffer.from(
          '<svg width="256" height="256"><circle cx="128" cy="128" r="50" fill="#B91C1C" /><circle cx="128" cy="128" r="30" fill="#7F1D1D" /></svg>'
        ),
        top: 0,
        left: 0
      }
    ])
    .png()
    .toBuffer();

  // Identical image
  const ssimIdentical = await ScreeningDeltaAnalyzer.calculateMSSIM(baseImg, baseImg);
  assert(ssimIdentical === 1.0, `Identical images yield SSIM = 1.000 (got ${ssimIdentical})`);

  // Uniform solid black image (potential division-by-zero check with variance=0, mean=0)
  const solidBlack = await sharp({
    create: {
      width: 128,
      height: 128,
      channels: 3,
      background: { r: 0, g: 0, b: 0 }
    }
  }).png().toBuffer();

  const ssimBlack = await ScreeningDeltaAnalyzer.calculateMSSIM(solidBlack, solidBlack);
  assert(!isNaN(ssimBlack) && isFinite(ssimBlack), `Zero-variance solid black image avoids NaN / division-by-zero (got ${ssimBlack})`);
  assert(ssimBlack === 1.0, `Two identical flat black images yield SSIM = 1.0`);

  // Uniform solid white vs solid black
  const solidWhite = await sharp({
    create: {
      width: 128,
      height: 128,
      channels: 3,
      background: { r: 255, g: 255, b: 255 }
    }
  }).png().toBuffer();

  const ssimContrast = await ScreeningDeltaAnalyzer.calculateMSSIM(solidBlack, solidWhite);
  assert(!isNaN(ssimContrast) && isFinite(ssimContrast), `Opposite uniform fields evaluate safely without division-by-zero (got ${ssimContrast})`);
  assert(ssimContrast < 0.05, `Max contrast black vs white yields near-zero SSIM (got ${ssimContrast})`);

  // Significant blur / morphological alteration on lesion image
  const modifiedImg = await sharp(baseImg)
    .blur(15)
    .png()
    .toBuffer();

  const ssimBlurred = await ScreeningDeltaAnalyzer.calculateMSSIM(baseImg, modifiedImg);
  assert(
    ssimBlurred >= 0.60 && ssimBlurred < 0.99,
    `Blurred lesion image yields moderate/high structural concordance (got ${ssimBlurred})`
  );

  // -------------------------------------------------------------
  // TEST 3: Clinical Delta Priority & Progression Status (Guardrail 2)
  // -------------------------------------------------------------
  console.log('\n--- TEST 3: Clinical Progression Categorization & Vital Deltas (Guardrail 2) ---');

  // Case A: Deteriorating / Escalating (Risk rises from 0.35 to 0.72)
  const compEscalating = await ScreeningDeltaAnalyzer.analyzeDelta(scr1Alpha, scr2Alpha, {
    baselineImageBuffer: baseImg,
    followupImageBuffer: modifiedImg
  });

  assert(compEscalating.status === 'Deteriorating / Escalating', `Case A categorizes as "Deteriorating / Escalating" (got "${compEscalating.status}")`);
  assert(compEscalating.riskDelta === 0.37, `Risk delta is +0.37 (got ${compEscalating.riskDelta})`);
  assert(compEscalating.riskDeltaPercentage === 37.0, `Risk delta percentage is +37.0% (got ${compEscalating.riskDeltaPercentage}%)`);
  assert(compEscalating.vitalsDelta.painDelta === 3, `Pain delta is +3 (got ${compEscalating.vitalsDelta.painDelta})`);
  assert(compEscalating.vitalsDelta.tempDelta === 1.1, `Temperature delta is +1.1°C (got ${compEscalating.vitalsDelta.tempDelta})`);
  assert(compEscalating.ssim !== null && compEscalating.ssim >= 0.7, `SSIM computed (got ${compEscalating.ssim})`);
  assert(compEscalating.recommendations.length >= 2, 'Actionable clinical recommendations provided for escalation');

  // Case B: Improving / Healing (Risk drops from 0.72 to 0.18)
  const compHealing = await ScreeningDeltaAnalyzer.analyzeDelta(scr2Alpha, scr3Alpha);
  assert(compHealing.status === 'Improving / Healing', `Case B categorizes as "Improving / Healing" (got "${compHealing.status}")`);
  assert(compHealing.riskDelta < -0.4, `Risk delta is negative reduction (got ${compHealing.riskDelta})`);
  assert(compHealing.vitalsDelta.painDelta === -5, `Pain delta decreased by -5 (got ${compHealing.vitalsDelta.painDelta})`);

  // Case C: Stable / Unchanged (Risk shift within 2%)
  const scrStable1: DBHealthScreeningRow = {
    id: 'scr-stable-1',
    patient_id: 'pt-gamma-303',
    previous_screening_id: null,
    institution_id: 'inst-test',
    image_url: null,
    symptom_payload: { vitals: { pain_score: 2, temperature: 36.8 } },
    multimodal_risk_score: 0.42,
    uncertaintyBounds: {},
    xai_heatmap_url: null,
    clinical_findings: [],
    risk_level: 'MODERATE',
    status: 'COMPLETED',
    created_at: new Date(Date.now() - 86400000).toISOString(),
    updated_at: new Date(Date.now() - 86400000).toISOString()
  } as any;

  const scrStable2: DBHealthScreeningRow = {
    id: 'scr-stable-2',
    patient_id: 'pt-gamma-303',
    previous_screening_id: 'scr-stable-1',
    institution_id: 'inst-test',
    image_url: null,
    symptom_payload: { vitals: { pain_score: 2, temperature: 36.9 } },
    multimodal_risk_score: 0.43,
    uncertaintyBounds: {},
    xai_heatmap_url: null,
    clinical_findings: [],
    risk_level: 'MODERATE',
    status: 'COMPLETED',
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString()
  } as any;

  const compStable = await ScreeningDeltaAnalyzer.analyzeDelta(scrStable1, scrStable2);
  assert(compStable.status === 'Stable / Unchanged', `Case C categorizes as "Stable / Unchanged" (got "${compStable.status}")`);
  assert(compStable.riskDelta === 0.01, `Risk delta is small +0.01 (got ${compStable.riskDelta})`);
  assert(compStable.ssim === null, 'Text-only screenings without images safely return null SSIM');
  assert(compStable.ssimCategory === 'N/A', 'SSIM category is N/A when images are omitted');

  // -------------------------------------------------------------
  // TEST 4: Timeline Sequence & Chronological Progression
  // -------------------------------------------------------------
  console.log('\n--- TEST 4: Timeline Chronological Query ---');

  const alphaTimeline = await HealthScreeningsDbService.getScreeningsByPatientAsc(patientAlpha);
  assert(alphaTimeline.length === 3, `Patient Alpha has 3 chronological screenings (got ${alphaTimeline.length})`);
  assert(alphaTimeline[0].id === scr1Alpha.id, 'First screening in timeline is T0 baseline');
  assert(alphaTimeline[1].id === scr2Alpha.id, 'Second screening in timeline is T1 follow-up');
  assert(alphaTimeline[2].id === scr3Alpha.id, 'Third screening in timeline is T2 resolution');

  console.log('\n================================================================');
  console.log(`📊 Longitudinal Progression Test Summary: ${passed} passed, ${failed} failed`);
  console.log('================================================================\n');

  if (failed > 0) {
    process.exit(1);
  }
}

runLongitudinalTests().catch((err) => {
  console.error('Fatal test error:', err);
  process.exit(1);
});
