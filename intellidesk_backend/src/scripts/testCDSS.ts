/**
 * Comprehensive Automated Verification Test Suite for CDSS Module
 * Tests:
 * 1. WHO ICD-11 URI & Subsumption Matching (Guardrail 1)
 * 2. Softmax Temperature Scaling & Logit Clipping (Guardrail 2)
 * 3. Evidence-Based Treatment Pathways (Labs, Imaging, Rx)
 * 4. Clinician Override & Medico-Legal Provenance (Guardrail 3)
 * 5. FHIR R4 DiagnosticReport Linkage (Guardrail 3)
 * 6. Offline Fallback & In-Memory Store Isolation (Guardrail 4)
 */

import { ICD11ConceptStore } from '../modules/cdss/ICD11ConceptStore.js';
import { DifferentialDiagnosisEngine } from '../modules/cdss/DifferentialDiagnosisEngine.js';
import { TreatmentPathwayAdvisor } from '../modules/cdss/TreatmentPathwayAdvisor.js';
import { CDSSService } from '../modules/cdss/CDSSService.js';
import { FHIRConverterService } from '../modules/diagnostics/fhir/FHIRConverterService.js';
import { assessMultimodalRisk } from '../modules/diagnostics/fusion/assessMultimodalRisk.js';
import {
  CDSSInputPayload,
  MANDATORY_CDSS_DISCLAIMER,
  WHO_ICD11_URI_STEM
} from '../modules/cdss/types.js';

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

async function runCDSSSuite() {
  console.log('\n======================================================');
  console.log('🩺 RUNNING CLINICAL DECISION SUPPORT SYSTEM (CDSS) TEST SUITE');
  console.log('======================================================\n');

  CDSSService.clearInMemoryStore();

  // 1. Guardrail 1: WHO ICD-11 URI & Subsumption Matching
  console.log('--- Test Group 1: WHO ICD-11 URI & Subsumption Matching (Guardrail 1) ---');
  {
    const concept = ICD11ConceptStore.getConceptByCode('1B10.0');
    assert(concept !== undefined, 'Found concept 1B10.0 by exact code');
    assert(
      concept?.uri === `${WHO_ICD11_URI_STEM}/1B10.0`,
      'URI matches exact WHO ICD-11 stem',
      `Got: ${concept?.uri}`
    );

    // Subsumption check
    const subsumed = ICD11ConceptStore.getConceptByCode('1B10');
    assert(subsumed !== undefined && subsumed.code === '1B10.0', 'Subsumption maps 1B10 to 1B10.0');

    // URI stem lookup check
    const fromUri = ICD11ConceptStore.getConceptByUri(`${WHO_ICD11_URI_STEM}/CA00`);
    assert(fromUri !== undefined && fromUri.code === 'CA00', 'Found concept CA00 from full WHO URI stem');

    const pneumonia = ICD11ConceptStore.getConceptByCode('CA40');
    assert(pneumonia !== undefined && pneumonia.title.includes('Pneumonia'), 'Found Pneumonia concept CA40');

    const hypertension = ICD11ConceptStore.getConceptByCode('BA00');
    assert(hypertension !== undefined && hypertension.category === 'Cardiovascular Diseases', 'Found Essential Hypertension BA00');
  }

  // 2. Guardrail 2: Softmax Temperature Scaling & Logit Clipping [-20, 20]
  console.log('\n--- Test Group 2: Softmax Temperature Scaling & Logit Clipping (Guardrail 2) ---');
  {
    const payload: CDSSInputPayload = {
      patientId: 'patient-test-01',
      multimodalRiskScore: 0.45,
      symptoms: {
        symptoms: ['cough', 'rhinorrhea', 'sore throat'],
        bodyLocation: 'Throat / Oral Cavity',
        vitals: {
          temperatureCelsius: 38.2,
          heartRate: 92
        }
      },
      audioClassification: {
        predictedCategory: 'Wet/Productive Cough',
        confidence: 0.85
      }
    };

    // Evaluate with standard temperature T = 1.25
    const candidates = DifferentialDiagnosisEngine.evaluateCandidates(payload, 1.25);
    assert(candidates.length >= 3, 'Returns at least 3 ranked DDx candidates', `Count: ${candidates.length}`);

    // Sum of probabilities must equal 1.0 within floating point rounding
    const sumProb = candidates.reduce((acc, c) => acc + c.probability, 0);
    console.log(`    Top DDx: ${candidates[0].code} (${candidates[0].title}) - P = ${(candidates[0].probability * 100).toFixed(1)}%`);
    console.log(`    Runner up: ${candidates[1].code} - P = ${(candidates[1].probability * 100).toFixed(1)}%`);

    assert(Math.abs(sumProb - 1.0) < 0.05, 'Probabilities sum to approximately 1.0', `Sum: ${sumProb}`);
    assert(candidates[0].code === '1B10.0' || candidates[0].code === 'CA00', 'Top candidate is Acute Respiratory Infection or Bronchitis');

    // Extreme Logit Clipping Test: Verify no NaN / Infinity with massive input scores
    const extremePayload: CDSSInputPayload = {
      patientId: 'extreme-test',
      multimodalRiskScore: 0.99,
      symptoms: {
        symptoms: Array.from({ length: 50 }, () => 'cough wheezing fever chills'),
        bodyLocation: 'Chest / Thorax',
        vitals: {
          temperatureCelsius: 41.5,
          heartRate: 160,
          oxygenSaturation: 82,
          respirationRate: 35,
          systolicBP: 210
        }
      }
    };

    const extremeCandidates = DifferentialDiagnosisEngine.evaluateCandidates(extremePayload, 1.2);
    assert(
      extremeCandidates.every((c) => !isNaN(c.probability) && isFinite(c.probability)),
      'Logit clipping [-20, 20] guarantees zero NaN/Infinity under extreme inputs'
    );
  }

  // 3. Evidence-Based Treatment Pathways
  console.log('\n--- Test Group 3: Evidence-Based Treatment Pathways ---');
  {
    const ddxCandidate = {
      code: 'CA40',
      title: 'Community-Acquired Pneumonia',
      category: 'Infectious Diseases',
      uri: `${WHO_ICD11_URI_STEM}/CA40`,
      probability: 0.72,
      logitScore: 8.5,
      matchedCriteria: ['Fever', 'Hypoxia', 'Productive Cough'],
      clinicalRationale: 'Hypoxia (SpO2 88%) with productive cough'
    };

    const pathway = TreatmentPathwayAdvisor.recommendPathway(ddxCandidate, 0.75);

    assert(pathway.primaryCode === 'CA40', 'Pathway matches primary ICD code CA40');
    assert(pathway.urgencyLevel === 'IMMEDIATE_EMERGENCY', 'Urgency level is IMMEDIATE_EMERGENCY for Pneumonia');
    assert(pathway.recommendedRx.some((rx) => rx.genericName.includes('Amoxicillin')), 'Prescribes first-line Amoxicillin/Clavulanate');
    assert(pathway.labOrders.some((lab) => lab.includes('CBC') || lab.includes('CRP')), 'Orders CBC and CRP lab tests');
    assert(pathway.imagingOrders.some((img) => img.includes('Chest Radiography')), 'Orders diagnostic Chest Radiography');
    assert(pathway.followUpDays <= 2, 'Follow-up is within 48 hours for high-risk pneumonia');
  }

  // 4. CDSS Service, Regulatory Disclaimer, and Clinician Override (Guardrail 3 & 4)
  console.log('\n--- Test Group 4: Clinician Approval & Medico-Legal Provenance (Guardrail 3) ---');
  {
    const evaluation = await CDSSService.evaluateScreening({
      screeningId: 'scr-100-test',
      patientId: 'student-900',
      multimodalRiskScore: 0.30,
      symptoms: {
        symptoms: ['pruritus / itching', 'erythema / redness', 'rash'],
        bodyLocation: 'Skin / Epidermis'
      },
      visionFindings: [{ condition: 'Dermatological Rash', confidence: 0.88 }]
    });

    assert(evaluation.regulatoryDisclaimer === MANDATORY_CDSS_DISCLAIMER, 'Mandatory regulatory disclaimer present (Guardrail 1)');
    assert(evaluation.primaryICD11Code === 'FB80', 'Primary ICD code mapped to FB80 (Contact Dermatitis)');
    assert(evaluation.attendingClinicianApproval === null, 'Initial evaluation has null approval');

    // Clinician performs manual override (e.g., changes FB80 to QC10 Acute Pain)
    const approved = await CDSSService.approveEvaluation(evaluation.id, {
      clinicianId: 'cmo-dr-smith',
      clinicianName: 'Dr. Gregory Smith, MD',
      isOverridden: true,
      overriddenCode: 'QC10',
      overrideNotes: 'Patient experiencing severe localized neuro-dermal pain requiring analgesia.'
    });

    assert(approved.attendingClinicianApproval !== null, 'Clinician approval registered');
    assert(approved.attendingClinicianApproval?.isOverridden === true, 'Approval marked as overridden');
    assert(approved.attendingClinicianApproval?.originalCode === 'FB80', 'Preserves original AI code FB80 (Guardrail 3)');
    assert(approved.attendingClinicianApproval?.overriddenCode === 'QC10', 'Preserves overridden code QC10 (Guardrail 3)');
    assert(
      approved.attendingClinicianApproval?.signatureHash.length === 64,
      'Generates 64-char SHA256 non-repudiation signature hash'
    );
    assert(approved.primaryICD11Code === 'QC10', 'Primary ICD code updated to overridden code');
    assert(approved.treatmentPathway.primaryCode === 'QC10', 'Treatment pathway regenerated for overridden code');
  }

  // 5. FHIR R4 DiagnosticReport Linkage (Guardrail 3)
  console.log('\n--- Test Group 5: FHIR R4 DiagnosticReport Linkage (Guardrail 3) ---');
  {
    const mockScreeningRow: any = {
      id: 'scr-fhir-test-1',
      patient_id: 'patient-456',
      institution_id: 'test-clinic',
      multimodal_risk_score: 0.68,
      risk_level: 'MODERATE',
      symptom_payload: {
        bodyLocation: 'Chest / Thorax',
        symptoms: ['cough', 'wheezing']
      },
      created_at: new Date().toISOString()
    };

    const cdssResult = {
      primaryICD11Code: 'CA00',
      primaryICD11Title: 'Acute Bronchitis'
    };

    const bundle = FHIRConverterService.buildFHIRDiagnosticReport(mockScreeningRow, cdssResult);
    const reportEntry = bundle.entry.find((e) => e.resource.resourceType === 'DiagnosticReport');
    const diagnosticReport = reportEntry?.resource as any;

    assert(diagnosticReport !== undefined, 'FHIR bundle contains DiagnosticReport resource');
    assert(Array.isArray(diagnosticReport.conclusionCode), 'DiagnosticReport has conclusionCode array');

    const icdCoding = diagnosticReport.conclusionCode.flatMap((cc: any) => cc.coding || [])
      .find((c: any) => c.system === WHO_ICD11_URI_STEM);

    assert(icdCoding !== undefined, 'Attached conclusionCode contains WHO ICD-11 system URI (Guardrail 1)');
    assert(icdCoding?.code === 'CA00', 'ICD-11 code matches CA00');
    assert(icdCoding?.display === 'Acute Bronchitis', 'ICD-11 display matches Acute Bronchitis');
  }

  // 6. Test Group 6: Anatomical Location Masking & Ocular Intake Verification
  console.log('\n--- Test Group 6: Anatomical Masking & Ocular Intake Verification ---');
  {
    // Test Intake Specification:
    // Location: Eye / Ophthalmology
    // Symptoms: Erythema / Redness, Pruritus / Itching
    // Vitals: Normal
    // Audio: Normal
    const ocularPayload: CDSSInputPayload = {
      patientId: 'patient-ocular-test-1',
      multimodalRiskScore: 0.25,
      symptoms: {
        bodyLocation: 'Eye / Ophthalmology',
        symptoms: ['Erythema / Redness', 'Pruritus / Itching'],
        vitals: {
          temperatureCelsius: 36.8,
          heartRate: 72,
          oxygenSaturation: 99,
          respirationRate: 16
        }
      },
      audioClassification: {
        predictedCategory: 'Normal Respiratory',
        confidence: 0.95
      }
    };

    const ddxCandidates = DifferentialDiagnosisEngine.evaluateCandidates(ocularPayload, 1.25);
    console.log(`    Evaluated DDx Candidates count: ${ddxCandidates.length}`);
    for (let i = 0; i < Math.min(5, ddxCandidates.length); i++) {
      console.log(`    #${i + 1}: ${ddxCandidates[i].code} (${ddxCandidates[i].title}) - P = ${(ddxCandidates[i].probability * 100).toFixed(2)}% | Logit: ${ddxCandidates[i].logitScore}`);
    }

    const topCandidate = ddxCandidates[0];
    const urtiCandidate = ddxCandidates.find((c) => c.code === '1B10.0');
    const bronchitisCandidate = ddxCandidates.find((c) => c.code === 'CA00' || c.code === 'CA01');
    const asthmaCandidate = ddxCandidates.find((c) => c.code === 'CA0B');

    // Assertion 1: Top candidate is an ocular diagnosis (9A60 Infectious Conjunctivitis)
    assert(
      topCandidate.code === '9A60',
      'Top predicted ICD-11 candidate is 9A60 (Infectious Conjunctivitis)',
      `Got top: ${topCandidate.code} (${topCandidate.title}) with P=${(topCandidate.probability * 100).toFixed(1)}%`
    );

    // Assertion 2: Purely respiratory codes receive 0% probability
    assert(
      urtiCandidate !== undefined && urtiCandidate.probability === 0.0,
      'Acute URTI (1B10.0) receives strict 0.0% probability when anatomy is Eye / Ophthalmology',
      `Got URTI P=${urtiCandidate ? urtiCandidate.probability : 'undefined'}`
    );

    if (bronchitisCandidate) {
      assert(
        bronchitisCandidate.probability === 0.0,
        'Bronchitis (CA00/CA01) receives strict 0.0% probability',
        `Got Bronchitis P=${bronchitisCandidate.probability}`
      );
    }

    if (asthmaCandidate) {
      assert(
        asthmaCandidate.probability === 0.0,
        'Asthma (CA0B) receives strict 0.0% probability',
        `Got Asthma P=${asthmaCandidate.probability}`
      );
    }

    // Assertion 3: CDSSService full evaluation returns 9A60 and evidence-based ophthalmic pathway
    const serviceEvaluation = await CDSSService.evaluateScreening(ocularPayload);
    assert(
      serviceEvaluation.primaryICD11Code === '9A60',
      'CDSSService assigns primaryICD11Code 9A60 for ocular intake'
    );
    assert(
      serviceEvaluation.treatmentPathway.primaryCode === '9A60',
      'Treatment pathway generated for 9A60 (Infectious Conjunctivitis)'
    );
    assert(
      serviceEvaluation.treatmentPathway.recommendedRx.some((rx) => rx.genericName.toLowerCase().includes('erythromycin')),
      'Prescribes first-line topical ophthalmic antibiotic (Erythromycin)'
    );

    // Assertion 3b: Clinical Assessment Result Screen click verification
    // When invoked with primaryDiagnosis: 'Infectious Conjunctivitis' (even if anatomicalLocation is absent in symptoms map)
    const resultsScreenPayload: CDSSInputPayload = {
      patientId: 'patient-eye-002',
      multimodalRiskScore: 0.45,
      symptoms: {
        primaryDiagnosis: 'Infectious Conjunctivitis',
        clinicalSummary: 'Infectious Conjunctivitis. Rest and artificial tears recommended.',
        recommendations: ['Topical ocular antibiotic', 'Warm compress'],
        riskLevel: 'MODERATE'
      } as any
    };
    const resultsDdx = DifferentialDiagnosisEngine.evaluateCandidates(resultsScreenPayload, 1.25);
    const resultsTop = resultsDdx[0];
    const resultsUrti = resultsDdx.find((c) => c.code === '1B10.0');

    assert(
      resultsTop.code === '9A60',
      'Clinical Assessment Screen: defaults to 9A60 (Infectious Conjunctivitis)',
      `Got top: ${resultsTop.code} (${resultsTop.title})`
    );
    assert(
      resultsUrti !== undefined && resultsUrti.probability === 0.0,
      'Clinical Assessment Screen: Acute URTI (1B10.0) masked to strict 0.0%',
      `Got URTI P=${resultsUrti?.probability}`
    );

    // Assertion 4: Multimodal Attention Weight Shift in Late-Fusion Layer
    // Non-respiratory anatomy + Normal audio -> audio modality weight = 0.05, visual modality weight = 0.70
    const multimodalRisk = await assessMultimodalRisk({
      symptomData: {
        bodyLocation: 'Eye / Ophthalmology',
        symptoms: ['Erythema / Redness', 'Pruritus / Itching']
      },
      audioClassification: {
        predictedCategory: 'Normal Respiratory',
        confidence: 0.95,
        probabilities: {
          normalRespiratory: 0.95,
          dryIrritativeCough: 0.02,
          wetProductiveCough: 0.02,
          wheezeStridor: 0.01
        },
        isRedFlagRespiratory: false,
        featureVector: new Array(16).fill(0.25)
      }
    });

    console.log('    Multimodal Late-Fusion Feature Weights:', JSON.stringify(multimodalRisk.featureWeights));
    assert(
      multimodalRisk.featureWeights.visualContribution === 0.70,
      'Optical Vision modality weight boosted to 0.70 when anatomy is non-respiratory and audio is normal',
      `Got visual: ${multimodalRisk.featureWeights.visualContribution}`
    );
    assert(
      multimodalRisk.featureWeights.audioContribution === 0.05,
      'Acoustic modality weight set to 0.05 in Late-Fusion layer',
      `Got audio: ${multimodalRisk.featureWeights.audioContribution}`
    );
    assert(
      multimodalRisk.primaryDiagnosis.includes('Conjunctivitis') || multimodalRisk.primaryDiagnosis.includes('9A60'),
      'Multimodal primary diagnosis is ocular (Infectious Conjunctivitis) not Non-Specific Acute Malaise',
      `Got primaryDiagnosis: ${multimodalRisk.primaryDiagnosis}`
    );
  }

  console.log('\n======================================================');
  console.log(`🎉 ALL ${passed}/${total} CDSS TESTS PASSED SUCCESSFULLY!`);
  console.log('======================================================\n');
}

runCDSSSuite().catch((err) => {
  console.error('💥 CDSS Test Suite Failed:', err);
  process.exit(1);
});
