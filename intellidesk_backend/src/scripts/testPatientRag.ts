import 'dotenv/config';
import { PatientClinicalRagService } from '../services/patientClinicalRagService.js';
import { PharmacyDbService } from '../modules/pharmacy/pharmacyDbService.js';
import { generateClinicalCounselorResponse } from '../services/clinicalCounselorService.js';


function assert(condition: boolean, message: string) {
  if (!condition) {
    console.error(`❌ FAIL: ${message}`);
    process.exit(1);
  }
  console.log(`  ✅ PASS: ${message}`);
}

async function runPatientRagTests() {
  console.log('\n================================================================');
  console.log('🧪 Starting MedAccess AI Patient Clinical RAG Verification Suite');
  console.log('================================================================\n');

  const testPatientId = 'patient-rag-test-' + Date.now();

  // Seed test allergy & medication for the patient
  await PharmacyDbService.addPatientMedication({
    patientId: testPatientId,
    medicationName: 'Metformin Hydrochloride',
    activeIngredient: 'Metformin',
    dosage: '500mg',
    isActive: true
  });

  await PharmacyDbService.addPatientAllergy({
    patientId: testPatientId,
    allergenGroup: 'PENICILLINS',
    reactionDescription: 'Severe anaphylaxis and hives'
  });

  console.log('--- TEST 1: Retrieve Multi-Entity Patient Context ---');
  const ragContext = await PatientClinicalRagService.retrievePatientContext(testPatientId);
  assert(ragContext.patientId === testPatientId, 'Patient ID preserved in RAG context');
  assert(ragContext.medications.length >= 1, 'Retrieved active medications');
  assert(ragContext.medications.some(m => m.activeIngredient === 'Metformin'), 'Found Metformin in active medication dossier');
  assert(ragContext.allergies.length >= 1, 'Retrieved patient allergies');
  assert(ragContext.allergies.some(a => a.allergenGroup === 'PENICILLINS'), 'Found PENICILLINS allergy with reaction');

  console.log('\n--- TEST 2: Format RAG Context for Mental Health Counselor ---');
  const mentalHealthBlock = PatientClinicalRagService.formatRagContextForPrompt(ragContext, 'MENTAL_HEALTH');
  assert(mentalHealthBlock.includes('CLINICAL PATIENT DOSSIER'), 'Contains clinical dossier header');
  assert(mentalHealthBlock.includes('Metformin'), 'Personalized context mentions Metformin');
  assert(mentalHealthBlock.includes('PENICILLINS'), 'Personalized context mentions PENICILLINS allergy');
  assert(mentalHealthBlock.includes('Severe anaphylaxis and hives'), 'Context contains patient reaction description');
  console.log('   [Sample Mental Health Context]:\n', mentalHealthBlock.trim());

  console.log('\n--- TEST 3: Retrieve and Format Claim Copay Context ---');
  const claimContext = await PatientClinicalRagService.retrieveClaimContext('test-claim-uuid-demo');
  assert(claimContext !== null, 'Claim RAG retrieval returns non-null structure');
  const claimBlock = PatientClinicalRagService.formatRagContextForPrompt(claimContext, 'CLAIM_TRIAGE');
  assert(claimBlock.includes('CLINICAL CLAIMS & COPAY DOSSIER'), 'Contains claims dossier header');
  console.log('   [Sample Claim Triage Context]:\n', claimBlock.trim());

  console.log('\n--- TEST 4: Live Clinical Counselor Response with Claim Context ---');
  const counselorRes = await generateClinicalCounselorResponse(
    'test-claim-rag-001',
    'I am worried about my medical bill and feeling anxious.'
  );
  assert(counselorRes.reply.length > 10, 'Generated counselor reply');
  assert(typeof counselorRes.latencyMs === 'number', 'Latency measured');
  console.log(`   [Counselor AI Reply]: "${counselorRes.reply}" (Latency: ${counselorRes.latencyMs}ms)`);

  console.log('\n--- TEST 5: Graceful Degradation on Unknown Patient ---');
  const emptyContext = await PatientClinicalRagService.retrievePatientContext('unknown-patient-9999');
  assert(emptyContext.medications.length === 0, 'Handled empty medications safely');
  assert(emptyContext.allergies.length === 0, 'Handled empty allergies safely');
  const emptyBlock = PatientClinicalRagService.formatRagContextForPrompt(emptyContext, 'MENTAL_HEALTH');
  assert(emptyBlock.includes('Active Medications: None recorded'), 'Handled empty state in prompt format');

  console.log('\n================================================================');
  console.log('📊 Patient RAG Suite: ALL TESTS PASSED (0 FAILURES)');
  console.log('================================================================\n');

  process.exit(0);
}

runPatientRagTests().catch(err => {
  console.error('Unhandled test failure:', err);
  process.exit(1);
});
