import 'dotenv/config';
import { parsePrescriptionDocument, sanitizeOcrText, parseMedicationLine } from '../modules/pharmacy/PrescriptionOCRParser.js';
import { findBestRxNormMatch, calculateSimilarity } from '../modules/pharmacy/fuzzyMatcher.js';
import { DrugInteractionEngine } from '../modules/pharmacy/DrugInteractionEngine.js';
import { AllergySafetySentinel } from '../modules/pharmacy/AllergySafetySentinel.js';
import { PharmacyDbService } from '../modules/pharmacy/pharmacyDbService.js';
import { RxSentinelService } from '../modules/pharmacy/RxSentinelService.js';

let passed = 0;
let failed = 0;

function assert(condition: boolean, testName: string, detail?: string) {
  if (condition) {
    console.log(`  ✅ PASS: ${testName}`);
    passed++;
  } else {
    console.error(`  ❌ FAIL: ${testName}${detail ? ` - ${detail}` : ''}`);
    failed++;
  }
}

async function runTestSuite() {
  console.log('\n================================================================');
  console.log('🧪 Starting RxSentinel Prescription Parsing & DDI Safety Suite');
  console.log('================================================================\n');

  // Ensure clean test isolation
  PharmacyDbService.clearInMemoryStore();

  // -------------------------------------------------------------
  // TEST 1: OCR Text Sanitization & Character Swaps (Guardrail 3)
  // -------------------------------------------------------------
  console.log('--- TEST 1: OCR Text Sanitization & Character Swaps ---');
  const dirtyOcr1 = 'Rx Amoxicillin 5O0mg I-0-1 for 7 days';
  const clean1 = sanitizeOcrText(dirtyOcr1);
  assert(clean1.includes('500 mg') || clean1.includes('500mg'), 'Swaps capital "O" to "0" in "5O0mg"', `got: ${clean1}`);
  assert(clean1.includes('1-0-1'), 'Replaces "I" with "1" in "I-0-1"', `got: ${clean1}`);

  const dirtyOcr2 = 'Tab Lipitor 1O0mg l-0-1';
  const clean2 = sanitizeOcrText(dirtyOcr2);
  assert(clean2.includes('100 mg') || clean2.includes('100mg'), 'Swaps capital "O" to "0" in "1O0mg"', `got: ${clean2}`);
  assert(clean2.includes('1-0-1'), 'Replaces lowercase "l" with "1" in "l-0-1"', `got: ${clean2}`);

  // -------------------------------------------------------------
  // TEST 2: Fuzzy String Matching & Typo Resolution (Guardrail 1)
  // -------------------------------------------------------------
  console.log('\n--- TEST 2: Fuzzy String Matching & Zero-Crash Bounds ---');
  const typo1 = findBestRxNormMatch('Amoxcilin', 0.75);
  assert(typo1.isVerified === true, 'Resolves typo "Amoxcilin" to verified RxNorm concept');
  assert(typo1.activeIngredient.toLowerCase() === 'amoxicillin', 'Active ingredient is Amoxicillin', `got: ${typo1.activeIngredient}`);
  assert(typo1.confidence >= 0.85, 'Confidence score >= 0.85', `got: ${typo1.confidence}`);

  const typo2 = findBestRxNormMatch('Atorvastin', 0.75);
  assert(typo2.isVerified === true, 'Resolves typo "Atorvastin" to Atorvastatin');
  assert(typo2.activeIngredient.toLowerCase() === 'atorvastatin', 'Active ingredient is Atorvastatin');

  const typo3 = findBestRxNormMatch('Ibuprofin', 0.75);
  assert(typo3.isVerified === true, 'Resolves typo "Ibuprofin" to Ibuprofen');
  assert(typo3.activeIngredient.toLowerCase() === 'ibuprofen', 'Active ingredient is Ibuprofen');

  // Guardrail 1 Zero-crash bounds on complete nonsense
  const nonsense = findBestRxNormMatch('XyzQrst1234NotADrug', 0.75);
  assert(nonsense.isVerified === false, 'Nonsense term correctly flagged as unverified');
  assert(nonsense.activeIngredient === 'XyzQrst1234NotADrug', 'Retains raw string safely without throwing exception');
  assert(nonsense.confidence < 0.75, 'Confidence safely under threshold');

  // -------------------------------------------------------------
  // TEST 3: Prescription Parsing & Entity Extraction
  // -------------------------------------------------------------
  console.log('\n--- TEST 3: Prescription Document Parsing & Entity Extraction ---');
  const prescriptionSampleText = `
Dr. Sarah Jenkins, MD - University Medical Center
Patient: John Doe | Date: 2026-09-23
Rx
1. Tab Augmentin 625mg 1-0-1 for 7 days
2. Advil 400mg PRN for 3 days
3. Metformin 500mg BID for 1 month
`;

  const parsedDoc = await parsePrescriptionDocument(prescriptionSampleText);
  assert(parsedDoc.medications.length >= 3, 'Extracted at least 3 clinical medication entries', `got: ${parsedDoc.medications.length}`);

  const augmentin = parsedDoc.medications.find(m => m.brandName.toLowerCase().includes('augmentin') || m.activeIngredient.toLowerCase().includes('amoxicillin'));
  assert(!!augmentin, 'Identified Augmentin / Amoxicillin line');
  assert(augmentin?.dosage === '625mg' || augmentin?.dosage === '625 mg', 'Extracted dosage 625mg', `got: ${augmentin?.dosage}`);
  assert(augmentin?.frequency === '1-0-1', 'Extracted frequency 1-0-1', `got: ${augmentin?.frequency}`);
  assert(!!augmentin?.duration?.includes('7'), 'Extracted duration 7 days', `got: ${augmentin?.duration}`);

  const advil = parsedDoc.medications.find(m => m.brandName.toLowerCase().includes('advil') || m.activeIngredient.toLowerCase().includes('ibuprofen'));
  assert(!!advil, 'Identified Advil / Ibuprofen line');
  assert(advil?.activeIngredient.toLowerCase() === 'ibuprofen', 'Mapped Advil brand to Ibuprofen generic active ingredient');

  // -------------------------------------------------------------
  // TEST 3B: Noisy Real-World OCR with Addresses, Doctors, Diseases, Contextual Dosages & Shorthand Durations
  // -------------------------------------------------------------
  console.log('\n--- TEST 3B: Noisy Prescription OCR Filtering & Shorthand Precision ---');
  const noisyPrescriptionText = `
APOLLO SPECIALTY HOSPITALS
154/11 Bannerghatta Road, Opp IIM, Bangalore - 560076
Phone: +91-80-26304050 | Email: care@apollohospitals.com
Dr. Rajesh Sharma, MBBS, MD (Internal Medicine), FACC - Reg No: KMC-48291
Date: 26-Sep-2026 | UHID: APL-992144 | Room: OPD-304
Patient: Alice Cooper, 45 Yrs / Female
Vitals: BP 130/85 mmHg, Pulse 76 bpm, SpO2 99%, Temp 98.4 F, Wt 62 kg
Chief Complaints: Fever, headache, severe cough, and sore throat for 3 days
Diagnosis: Acute Upper Respiratory Tract Infection, Essential Hypertension
Rx
1. Tab. Augmentin 625 1-0-1 x 5/7
2. Dolo 650 TDS SOS
3. Pantocid 40 OD ac (14 days)
4. Azithral 500
   1-0-0 x 3 days
General Advice: Steam inhalation, drink plenty of warm water, bed rest
Review after 5 days with CBC reports
Doctor's Signature: Dr. R. Sharma
`;

  const noisyParsed = await parsePrescriptionDocument(noisyPrescriptionText);

  // Must only extract actual medications (Augmentin, Dolo, Pantocid, Azithral)
  assert(noisyParsed.medications.length === 4, `Extracted exactly 4 medications without noise (got: ${noisyParsed.medications.length})`);

  // Verify none of the non-medication words are present
  const extractedNames = noisyParsed.medications.map(m => m.brandName.toLowerCase() + ' ' + m.activeIngredient.toLowerCase()).join(' ');
  const forbiddenTerms = ['apollo', 'bannerghatta', 'bangalore', 'rajesh', 'sharma', 'alice', 'cooper', 'fever', 'headache', 'cough', 'hypertension', 'infection', 'vitals', 'advice', 'water', 'signature'];
  for (const term of forbiddenTerms) {
    assert(!extractedNames.includes(term), `Forbidden term "${term}" correctly rejected from medications list`);
  }

  // Verify Augmentin 625 dosage and 5/7 duration
  const aug = noisyParsed.medications.find(m => m.brandName.toLowerCase().includes('augmentin') || m.activeIngredient.toLowerCase().includes('amoxicillin'));
  assert(!!aug, 'Found Augmentin');
  assert(aug?.dosage === '625mg', `Extracted unitless contextual dosage 625mg (got: ${aug?.dosage})`);
  assert(aug?.frequency === '1-0-1', `Extracted frequency 1-0-1 (got: ${aug?.frequency})`);
  assert(aug?.duration === '5 days', `Extracted shorthand fraction 5/7 as 5 days (got: ${aug?.duration})`);

  // Verify Dolo 650 dosage, TDS frequency, SOS
  const dolo = noisyParsed.medications.find(m => m.brandName.toLowerCase().includes('dolo') || m.activeIngredient.toLowerCase().includes('acetaminophen'));
  assert(!!dolo, 'Found Dolo');
  assert(dolo?.dosage === '650mg', `Extracted unitless contextual dosage 650mg (got: ${dolo?.dosage})`);
  assert(dolo?.frequency === 'TID', `Standardized TDS frequency to TID (got: ${dolo?.frequency})`);

  // Verify Pantocid 40 OD (14 days)
  const panto = noisyParsed.medications.find(m => m.brandName.toLowerCase().includes('panto') || m.activeIngredient.toLowerCase().includes('pantoprazole'));
  assert(!!panto, 'Found Pantocid / Pantoprazole');
  assert(panto?.dosage === '40mg', `Extracted unitless dosage 40mg (got: ${panto?.dosage})`);
  assert(panto?.frequency === 'QD', `Standardized OD frequency to QD (got: ${panto?.frequency})`);
  assert(panto?.duration === '14 days', `Extracted duration 14 days (got: ${panto?.duration})`);

  // Verify multi-line Azithral continuation
  const azith = noisyParsed.medications.find(m => m.brandName.toLowerCase().includes('azith') || m.activeIngredient.toLowerCase().includes('azithromycin'));
  assert(!!azith, 'Found Azithral / Azithromycin merged continuation');
  assert(azith?.dosage === '500mg', `Extracted dosage 500mg (got: ${azith?.dosage})`);
  assert(azith?.duration === '3 days', `Extracted duration 3 days (got: ${azith?.duration})`);

  // -------------------------------------------------------------
  // TEST 4: Drug-Drug Interaction (DDI) Pairwise Engine
  // -------------------------------------------------------------
  console.log('\n--- TEST 4: Drug-Drug Interaction (DDI) Pairwise Engine ---');
  // High risk severe contraindicated pairs
  const ddiWarfarinAspirin = DrugInteractionEngine.checkPair('Warfarin', 'Aspirin');
  assert(ddiWarfarinAspirin.severity === 'CONTRAINDICATED_SEVERE', 'Warfarin + Aspirin triggers CONTRAINDICATED_SEVERE', `got: ${ddiWarfarinAspirin.severity}`);
  assert(ddiWarfarinAspirin.clinicalMechanism.includes('hemorrhage') || ddiWarfarinAspirin.clinicalMechanism.includes('anticoagulation'), 'Identified hemorrhagic clinical mechanism');

  const ddiSildenafilNitrate = DrugInteractionEngine.checkPair('Viagra', 'Nitroglycerin');
  assert(ddiSildenafilNitrate.severity === 'CONTRAINDICATED_SEVERE', 'Sildenafil (Viagra) + Nitroglycerin triggers CONTRAINDICATED_SEVERE');
  assert(ddiSildenafilNitrate.clinicalMechanism.includes('hypotension'), 'Identified severe hypotension mechanism');

  const ddiMethotrexateIbuprofen = DrugInteractionEngine.checkPair('Methotrexate', 'Ibuprofen');
  assert(ddiMethotrexateIbuprofen.severity === 'CONTRAINDICATED_SEVERE', 'Methotrexate + Ibuprofen triggers CONTRAINDICATED_SEVERE');

  // Moderate monitor pairs
  const ddiCiproCalcium = DrugInteractionEngine.checkPair('Ciprofloxacin', 'Calcium Carbonate');
  assert(ddiCiproCalcium.severity === 'MODERATE_MONITOR', 'Ciprofloxacin + Calcium Carbonate triggers MODERATE_MONITOR');
  assert(ddiCiproCalcium.clinicalMechanism.includes('chelation') || ddiCiproCalcium.clinicalMechanism.includes('bioavailability'), 'Identified chelation mechanism');

  // Safe pair
  const ddiSafe = DrugInteractionEngine.checkPair('Amoxicillin', 'Acetaminophen');
  assert(ddiSafe.severity === 'SAFE', 'Amoxicillin + Acetaminophen evaluates as SAFE');

  // Multi-drug evaluation
  const multiInteractions = DrugInteractionEngine.evaluateInteractions(
    ['Aspirin', 'Metformin'],
    ['Warfarin', 'Atorvastatin']
  );
  assert(multiInteractions.some(d => d.severity === 'CONTRAINDICATED_SEVERE'), 'Multi-drug check caught Warfarin + Aspirin severe conflict');

  // -------------------------------------------------------------
  // TEST 5: Allergy Safety Sentinel & Cross-Reactivity (Guardrail 2)
  // -------------------------------------------------------------
  console.log('\n--- TEST 5: Allergy Safety Sentinel & Cross-Reactivity ---');
  // Patient with documented Penicillin allergy
  const patientAllergies = [
    {
      patientId: 'patient-test-rx-001',
      allergenGroup: 'PENICILLINS',
      reactionDescription: 'Severe Anaphylaxis and Urticaria'
    },
    {
      patientId: 'patient-test-rx-001',
      allergenGroup: 'SULFA',
      reactionDescription: 'Stevens-Johnson rash'
    }
  ];

  // 1. Direct derivative match (Amoxicillin)
  const allergyConflicts1 = await AllergySafetySentinel.evaluateAllergies(['Amoxicillin 500mg'], patientAllergies);
  assert(allergyConflicts1.length === 1, 'Detected direct Penicillin allergy conflict for Amoxicillin');
  assert(allergyConflicts1[0].allergenGroup === 'PENICILLINS', 'Conflict allergen group is PENICILLINS');
  assert(allergyConflicts1[0].severity === 'HIGH_RISK_ALLERGY', 'Severity is HIGH_RISK_ALLERGY');
  assert(Array.isArray(allergyConflicts1[0].suggestedAlternatives) && allergyConflicts1[0].suggestedAlternatives.length > 0, 'Alternatives generated via NLM RxNav / Clinical Guideline');
  console.log(`   [Live Alternatives Verified] Generated ${allergyConflicts1[0]?.suggestedAlternatives?.length || 0} alternative(s): ${(allergyConflicts1[0]?.suggestedAlternatives || []).map((a: any) => a.activeIngredient + ' (' + a.source + ')').join(', ')}`);

  // 2. Cross-reactivity brand/child match (Augmentin)
  const allergyConflicts2 = await AllergySafetySentinel.evaluateAllergies(['Augmentin 625mg'], patientAllergies);
  assert(allergyConflicts2.length === 1, 'Cross-reactivity mapped Augmentin to PENICILLINS allergy');

  // 3. Sulfa derivative match (Bactrim)
  const allergyConflicts3 = await AllergySafetySentinel.evaluateAllergies(['Bactrim DS'], patientAllergies);
  assert(allergyConflicts3.length === 1, 'Cross-reactivity mapped Bactrim to SULFA allergy');

  // 4. Safe non-matching medication
  const safeAllergyCheck = await AllergySafetySentinel.evaluateAllergies(['Acetaminophen 500mg', 'Atorvastatin 20mg'], patientAllergies);
  assert(safeAllergyCheck.length === 0, 'No false-positive allergy conflicts for Acetaminophen or Atorvastatin');


  // -------------------------------------------------------------
  // TEST 6: RxSentinel Pipeline & Patient Safety Flag Override (Guardrail 3)
  // -------------------------------------------------------------
  console.log('\n--- TEST 6: RxSentinel Pipeline & Safety Flag Override ---');
  // Seed patient active medications in DB service
  await PharmacyDbService.addPatientMedication({
    patientId: 'pat-clinical-999',
    medicationName: 'Coumadin',
    activeIngredient: 'Warfarin',
    dosage: '5mg',
    isActive: true
  });

  // Seed patient allergy
  await PharmacyDbService.addPatientAllergy({
    patientId: 'pat-clinical-999',
    allergenGroup: 'NSAIDS',
    reactionDescription: 'Bronchospasm / Angioedema'
  });

  // Process prescription containing Aspirin (which is both NSAID allergy conflict AND Warfarin DDI)
  const rxInput = `
Rx: Aspirin 325mg QD
Tab Paracetamol 500mg PRN
`;

  const summary = await RxSentinelService.analyzePrescription({
    input: rxInput,
    patientId: 'pat-clinical-999',
    claimId: 'claim-rx-safety-check-001'
  });

  assert(summary.extractedDrugs.length >= 2, 'Parsed 2 drugs from prescription text');
  assert(summary.hasSafetyConflict === true, 'Safety conflict flag is TRUE');
  assert(summary.requiresPharmacistReview === true, 'requiresPharmacistReview is TRUE (Guardrail 3)');
  assert(summary.allergyConflicts.length >= 1, 'Caught NSAID allergy conflict with Aspirin');
  assert(summary.ddiWarnings.some(d => d.severity === 'CONTRAINDICATED_SEVERE'), 'Caught Warfarin + Aspirin severe DDI');

  // -------------------------------------------------------------
  // TEST 7: Test Isolation in Memory Fallbacks (Guardrail 2)
  // -------------------------------------------------------------
  console.log('\n--- TEST 7: Test Isolation in Memory Fallbacks ---');
  await PharmacyDbService.deletePatientMedication('Coumadin', 'pat-clinical-999');
  await PharmacyDbService.deletePatientAllergy('pat-clinical-999', 'NSAIDS');
  PharmacyDbService.clearInMemoryStore();
  const resetAllergies = await PharmacyDbService.getPatientAllergies('pat-clinical-999');
  const resetMeds = await PharmacyDbService.getPatientMedications('pat-clinical-999');
  assert(resetAllergies.length === 0, 'clearInMemoryStore & DB delete resets allergies store cleanly');
  assert(resetMeds.length === 0, 'clearInMemoryStore & DB delete resets medications store cleanly');

  // -------------------------------------------------------------
  // TEST 8: Medication & Allergy DB Deletion Lifecycle
  // -------------------------------------------------------------
  console.log('\n--- TEST 8: Database Medication & Allergy Deletion ---');
  const testPatient = 'PAT-TEST-DELETE-001';
  const createdMed1 = await PharmacyDbService.addPatientMedication({
    patientId: testPatient,
    medicationName: 'Atorvastatin 20mg',
    activeIngredient: 'Atorvastatin',
    dosage: '20mg daily',
    isActive: true
  });
  const createdMed2 = await PharmacyDbService.addPatientMedication({
    patientId: `usr_pat_${testPatient}`,
    medicationName: 'Metformin Hydrochloride 500mg',
    activeIngredient: 'Metformin',
    dosage: '500mg twice daily',
    isActive: true
  });

  const medsBefore = await PharmacyDbService.getPatientMedications(testPatient);
  assert(medsBefore.length >= 2, 'Retrieved active medications across patient ID variants', `count: ${medsBefore.length}`);

  // Delete createdMed1 by UUID
  const delMed1 = await PharmacyDbService.deletePatientMedication(createdMed1.id!, testPatient);
  assert(delMed1 === true, 'Successfully deleted medication 1 by UUID');

  // Delete createdMed2 by Name with prefix variant
  const delMed2 = await PharmacyDbService.deletePatientMedication('Metformin', testPatient);
  assert(delMed2 === true, 'Successfully deleted medication 2 by name with patient ID normalization');

  const medsAfter = await PharmacyDbService.getPatientMedications(testPatient);
  assert(
    !medsAfter.some(m => m.id === createdMed1.id || m.medicationName.includes('Metformin')),
    'Deleted medications are completely purged from database and memory'
  );

  console.log('\n================================================================');
  console.log(`📊 RxSentinel Test Summary: ${passed} passed, ${failed} failed`);
  console.log('================================================================\n');

  if (failed > 0) {
    process.exit(1);
  }
}

runTestSuite().catch((err) => {
  console.error('💥 Fatal error in RxSentinel test runner:', err);
  process.exit(1);
});
