import { DBHealthScreeningRow } from '../modules/diagnostics/db/healthScreeningsDbService.js';
import { FHIRConverterService } from '../modules/diagnostics/fhir/FHIRConverterService.js';
import { ReferralLetterGenerator } from '../modules/diagnostics/fhir/ReferralLetterGenerator.js';
import {
  LOINC_SYSTEM,
  UCUM_SYSTEM,
  OBSERVATION_INTERPRETATION_SYSTEM,
  CLINICAL_CODINGS
} from '../modules/diagnostics/fhir/types.js';

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

async function runFHIRAndReferralTests(): Promise<void> {
  console.log('\n================================================================');
  console.log('🧪 Starting HL7 FHIR R4 & Clinical Referral Letter Test Suite');
  console.log('================================================================\n');

  // Sample Critical Screening Record
  const criticalScreening: DBHealthScreeningRow = {
    id: 'scr-crit-90210',
    patient_id: 'pat-clinical-884',
    institution_id: 'mass-general-triage',
    image_url: 'https://images.unsplash.com/photo-1576091160399-112ba8d25d1d?w=300',
    symptom_payload: {
      bodyLocation: 'Chest / Thorax',
      durationDays: 2,
      painScale: 9,
      symptoms: ['acute chest tightness', 'wheezing', 'dyspnea'],
      vitals: {
        temperatureCelsius: 39.4,
        heartRate: 118,
        systolicBP: 154,
        diastolicBP: 98,
        oxygenSaturation: 88.5,
        respiratoryRate: 28
      },
      demographics: {
        age: 62,
        gender: 'Male',
        preExistingConditions: ['COPD', 'Hypertension']
      },
      additionalNotes: 'Severe inspiratory wheezing with bilateral basal rales.'
    },
    multimodal_risk_score: 0.88,
    uncertainty_bounds: {
      ciLower: 0.84,
      ciUpper: 0.92,
      epistemicStdDev: 0.028,
      epistemicVariance: 0.000784,
      monteCarloSamples: 10
    },
    xai_heatmap_url: 'data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxMDAiIGhlaWdodD0iMTAwIj48cmVjdCB3aWR0aD0iMTAwIiBoZWlnaHQ9IjEwMCIgZmlsbD0icmVkIi8+PC9zdmc+',
    clinical_findings: [
      { condition: 'Acute Respiratory Distress / Severe Bronchospasm', confidence: 0.89 },
      { condition: 'Pneumonia / Lower Respiratory Infection', confidence: 0.74 }
    ],
    risk_level: 'CRITICAL',
    status: 'COMPLETED',
    created_at: new Date('2026-09-23T10:30:00Z').toISOString(),
    updated_at: new Date('2026-09-23T10:31:00Z').toISOString()
  };

  // Sample Anonymous Moderate Screening Record
  const anonymousScreening: DBHealthScreeningRow = {
    id: 'scr-anon-44123',
    patient_id: null, // Anonymous intake
    institution_id: 'community-clinic-4',
    image_url: null,
    symptom_payload: {
      bodyLocation: 'Left Forearm',
      durationDays: 5,
      painScale: 5,
      symptoms: ['erythematous rash', 'localized pruritus'],
      vitals: {
        temperatureCelsius: 37.6,
        heartRate: 78,
        systolicBP: 122,
        diastolicBP: 78,
        oxygenSaturation: 98.0
      },
      demographics: {
        age: 34,
        gender: 'Female',
        preExistingConditions: ['Atopic Dermatitis']
      }
    },
    multimodal_risk_score: 0.48,
    uncertainty_bounds: {
      ciLower: 0.44,
      ciUpper: 0.52,
      epistemicStdDev: 0.035,
      epistemicVariance: 0.001225
    },
    xai_heatmap_url: null,
    clinical_findings: [
      { condition: 'Mild Contact Dermatitis', confidence: 0.65 }
    ],
    risk_level: 'MODERATE',
    status: 'COMPLETED',
    created_at: new Date('2026-09-23T11:15:00Z').toISOString(),
    updated_at: new Date('2026-09-23T11:16:00Z').toISOString()
  };

  // -----------------------------------------------------------------
  // TEST 1: Strict LOINC & UCUM Standard Alignment (Guardrail 2)
  // -----------------------------------------------------------------
  console.log('\n--- TEST 1: Strict LOINC & UCUM Standard Alignment in Observation ---');
  {
    const obs = FHIRConverterService.buildFHIRObservation(criticalScreening);

    assert(obs.resourceType === 'Observation', 'resourceType is "Observation"');
    assert(obs.id === 'obs-scr-crit-90210', 'Observation id correctly mapped');
    assert(obs.status === 'final', 'Observation status is "final"');

    // Risk Score LOINC Code
    assert(
      obs.code.coding[0].system === LOINC_SYSTEM && obs.code.coding[0].code === CLINICAL_CODINGS.RISK_SCORE.code,
      `Risk score mapped to LOINC 98144-9: ${obs.code.coding[0].code}`
    );
    assert(
      obs.valueQuantity?.value === 0.88 && obs.valueQuantity.code === '{score}',
      `Value quantity is 0.88 with UCUM code "{score}"`
    );

    // Verify Components Vitals Mapping
    const components = obs.component || [];
    assert(components.length >= 7, `Observation has at least 7 clinical components (actual: ${components.length})`);

    // Temperature (LOINC 8310-5, Cel)
    const tempComp = components.find(c => c.code.coding[0].code === '8310-5');
    assert(tempComp !== undefined, 'Body Temperature component found with LOINC 8310-5');
    assert(tempComp?.valueQuantity?.value === 39.4, 'Temperature value equals 39.4');
    assert(tempComp?.valueQuantity?.code === 'Cel', 'Temperature UCUM code strictly equals "Cel"');
    assert(tempComp?.valueQuantity?.system === UCUM_SYSTEM, 'Temperature system is UCUM');

    // Heart Rate (LOINC 8867-4, /min)
    const hrComp = components.find(c => c.code.coding[0].code === '8867-4');
    assert(hrComp !== undefined, 'Heart Rate component found with LOINC 8867-4');
    assert(hrComp?.valueQuantity?.value === 118, 'Heart Rate value equals 118');
    assert(hrComp?.valueQuantity?.code === '/min', 'Heart Rate UCUM code strictly equals "/min"');

    // Systolic Blood Pressure (LOINC 8480-6, mm[Hg])
    const sbpComp = components.find(c => c.code.coding[0].code === '8480-6');
    assert(sbpComp !== undefined, 'Systolic BP component found with LOINC 8480-6');
    assert(sbpComp?.valueQuantity?.value === 154, 'Systolic BP value equals 154');
    assert(sbpComp?.valueQuantity?.code === 'mm[Hg]', 'Systolic BP UCUM code strictly equals "mm[Hg]"');

    // Oxygen Saturation SpO2 (LOINC 2708-6, %)
    const spo2Comp = components.find(c => c.code.coding[0].code === '2708-6');
    assert(spo2Comp !== undefined, 'SpO2 component found with LOINC 2708-6');
    assert(spo2Comp?.valueQuantity?.value === 88.5, 'SpO2 value equals 88.5');
    assert(spo2Comp?.valueQuantity?.code === '%', 'SpO2 UCUM code strictly equals "%"');

    // Respiratory Rate (LOINC 9279-1, /min)
    const rrComp = components.find(c => c.code.coding[0].code === '9279-1');
    assert(rrComp !== undefined, 'Respiratory Rate component found with LOINC 9279-1');
    assert(rrComp?.valueQuantity?.value === 28, 'Respiratory Rate value equals 28');
    assert(rrComp?.valueQuantity?.code === '/min', 'Respiratory Rate UCUM code strictly equals "/min"');

    // Pain Scale (LOINC 72514-3, {score})
    const painComp = components.find(c => c.code.coding[0].code === '72514-3');
    assert(painComp !== undefined, 'Pain Severity component found with LOINC 72514-3');
    assert(painComp?.valueQuantity?.value === 9, 'Pain Severity value equals 9');
    assert(painComp?.valueQuantity?.code === '{score}', 'Pain Severity UCUM code strictly equals "{score}"');

    // Symptom Duration (LOINC 68516-4, d)
    const durComp = components.find(c => c.code.coding[0].code === '68516-4');
    assert(durComp !== undefined, 'Symptom Duration component found with LOINC 68516-4');
    assert(durComp?.valueQuantity?.value === 2, 'Symptom Duration value equals 2');
    assert(durComp?.valueQuantity?.code === 'd', 'Symptom Duration UCUM code strictly equals "d"');

    // Interpretation code: H for Critical
    assert(
      obs.interpretation?.[0].coding[0].code === 'H',
      `Critical risk interpreted with FHIR code "H": got ${obs.interpretation?.[0].coding[0].code}`
    );
  }

  // -----------------------------------------------------------------
  // TEST 2: Patient Reference Structural Safeguard (Guardrail 4)
  // -----------------------------------------------------------------
  console.log('\n--- TEST 2: Patient Reference Structural Safeguard (Guardrail 4) ---');
  {
    // Linked Patient Case
    const linkedObs = FHIRConverterService.buildFHIRObservation(criticalScreening);
    assert(
      linkedObs.subject.reference === 'Patient/pat-clinical-884',
      `Linked patient reference: ${linkedObs.subject.reference}`
    );
    assert(linkedObs.subject.type === 'Patient', 'Linked subject type is "Patient"');

    // Anonymous / Unlinked Case (Safeguard)
    const anonObs = FHIRConverterService.buildFHIRObservation(anonymousScreening);
    assert(
      anonObs.subject.reference.startsWith('urn:uuid:patient-deidentified-'),
      `Anonymous patient fallback reference: ${anonObs.subject.reference}`
    );
    assert(anonObs.subject.type === 'Patient', 'Anonymous subject type is "Patient"');
    assert(
      anonObs.subject.display === 'De-identified Patient (Intake Screening)',
      'Anonymous subject display clearly denotes de-identified intake'
    );

    // Moderate Risk Interpretation code: A
    assert(
      anonObs.interpretation?.[0].coding[0].code === 'A',
      `Moderate risk interpreted with FHIR code "A": got ${anonObs.interpretation?.[0].coding[0].code}`
    );
  }

  // -----------------------------------------------------------------
  // TEST 3: FHIR DiagnosticReport Bundle Compliance
  // -----------------------------------------------------------------
  console.log('\n--- TEST 3: FHIR DiagnosticReport Bundle Compliance ---');
  {
    const bundle = FHIRConverterService.buildFHIRDiagnosticReport(criticalScreening);

    assert(bundle.resourceType === 'Bundle', 'resourceType is "Bundle"');
    assert(bundle.type === 'collection', 'Bundle type is "collection"');
    assert(bundle.entry.length === 2, `Bundle contains 2 entries (actual: ${bundle.entry.length})`);

    const reportEntry = bundle.entry.find(e => (e.resource as any).resourceType === 'DiagnosticReport');
    const obsEntry = bundle.entry.find(e => (e.resource as any).resourceType === 'Observation');

    assert(reportEntry !== undefined, 'DiagnosticReport entry present in bundle');
    assert(obsEntry !== undefined, 'Observation entry present in bundle');

    const report = reportEntry!.resource as any;
    assert(report.id === 'diagrep-scr-crit-90210', `Report ID matches: ${report.id}`);
    assert(report.status === 'final', 'Report status is "final"');
    assert(report.result[0].reference === 'Observation/obs-scr-crit-90210', 'Report links to Observation');
    assert(report.media && report.media.length === 2, `Report attaches 2 media items (photo & heatmap)`);
    assert(report.conclusion.includes('CRITICAL (88% Risk Score)'), 'Report conclusion denotes risk score');
    assert(report.conclusionCode[0].coding[0].code === '410605003', 'Critical referral mapped to SNOMED 410605003');
  }

  // -----------------------------------------------------------------
  // TEST 4: Robust Image Rendering Fail-Safe in PDFKit (Guardrail 1)
  // -----------------------------------------------------------------
  console.log('\n--- TEST 4: Robust Image Rendering Fail-Safe in PDFKit (Guardrail 1) ---');
  {
    // Deliberately corrupt/unreachable image URLs to test fail-safe placeholder
    const failSafeScreening: DBHealthScreeningRow = {
      ...criticalScreening,
      id: 'scr-fail-safe-001',
      image_url: 'https://invalid-host-definitely-does-not-exist.test/nonexistent.jpg',
      xai_heatmap_url: 'data:image/svg+xml;base64,invalid-corrupted-svg-data'
    };

    console.log('  Generating referral PDF with corrupt/unreachable image sources...');
    const pdfBuffer = await ReferralLetterGenerator.generateReferralPdfBuffer(failSafeScreening);

    assert(pdfBuffer instanceof Buffer, 'Returned valid Buffer object');
    assert(pdfBuffer.length > 3500, `PDF Buffer size is substantial (${pdfBuffer.length} bytes)`);

    // Verify PDF header magic
    const header = pdfBuffer.subarray(0, 5).toString('ascii');
    assert(header === '%PDF-', `File header begins with "%PDF-" (got "${header}")`);

    // Verify PDF trailer
    const tail = pdfBuffer.subarray(pdfBuffer.length - 128).toString('ascii');
    assert(tail.includes('%%EOF'), 'File terminates with valid "%%EOF" marker');
  }

  // -----------------------------------------------------------------
  // TEST 5: Complete Clinical Referral Letter Document Generation
  // -----------------------------------------------------------------
  console.log('\n--- TEST 5: Clinical Referral Letter Document Generation (Critical & Moderate) ---');
  {
    // Case A: Critical Referral PDF
    const criticalPdf = await ReferralLetterGenerator.generateReferralPdfBuffer(criticalScreening);
    assert(criticalPdf.length > 8000, `Critical Referral PDF generated (${criticalPdf.length} bytes)`);

    // Case B: Moderate Need Referral PDF
    const moderatePdf = await ReferralLetterGenerator.generateReferralPdfBuffer(anonymousScreening);
    assert(moderatePdf.length > 3500, `Moderate Need Referral PDF generated (${moderatePdf.length} bytes)`);
  }

  console.log('\n================================================================');
  console.log(`📊 HL7 FHIR & Referral Test Summary: ${passedTests} passed, ${failedTests} failed`);
  console.log('================================================================\n');

  if (failedTests > 0) {
    process.exit(1);
  }
}

runFHIRAndReferralTests().catch(err => {
  console.error('Fatal error running FHIR & Referral tests:', err);
  process.exit(1);
});
