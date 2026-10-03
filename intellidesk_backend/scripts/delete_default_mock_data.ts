import 'dotenv/config';
import { supabase } from '../src/config/supabase.js';

async function deleteDefaultMockData() {
  console.log('🚨 [Mock Data Purge] Removing Alex Rivera, Maya Lin, Sarah Chen, and all default mock data from Supabase...');

  // 1. Purge default patient_rosters (keep only Priya Sharma)
  const defaultPatientIds = [
    'PAT-2026-001',
    'PAT-2026-003',
    'PAT-2026-004',
    'PAT-2026-005',
    'PAT-2026-006',
    'PAT-2026-007',
    'PAT-2026-008',
    'MED-PAT-1790276586930'
  ];

  console.log('\n🗑️ Cleaning default patient_rosters...');
  const { error: rosterErr } = await supabase
    .from('patient_rosters')
    .delete()
    .in('patient_id', defaultPatientIds);

  if (rosterErr) {
    console.error('❌ Error cleaning patient_rosters:', rosterErr.message);
  } else {
    console.log('✅ Cleaned default entries from patient_rosters.');
  }

  // Also clean any by email
  await supabase
    .from('patient_rosters')
    .delete()
    .in('email', [
      'alex.rivera@campushealth.edu',
      'marcus.chen@campushealth.edu',
      'elena.rostova@campushealth.edu',
      'jordan.taylor@campushealth.edu',
      'sophia.r@campushealth.edu',
      'rohan.gupta@campushealth.edu',
      'maya.lin@campushealth.edu',
      'patient@apexhealth.edu'
    ]);

  // 2. Purge default profiles (Maya Lin, Dr. Sarah Chen, or any non-Priya/non-Aditya mock profile)
  console.log('\n🗑️ Cleaning default profiles...');
  const { error: profileErr } = await supabase
    .from('profiles')
    .delete()
    .in('email', [
      'maya.lin@campushealth.edu',
      'admin@campushealth.edu',
      'alex.rivera@campushealth.edu'
    ]);

  if (profileErr) {
    console.error('❌ Error cleaning profiles:', profileErr.message);
  } else {
    console.log('✅ Cleaned default profiles (Maya Lin, Dr. Sarah Chen).');
  }

  // 3. Purge patient_allergies for default demo patients
  console.log('\n🗑️ Cleaning default patient_allergies...');
  const demoAllergyPatientIds = [
    'PAT-2026-001',
    'usr_pat_PAT-2026-001',
    'usr_pat_001',
    'guest-patient',
    'patient-rag-test-1790849153246'
  ];
  const { error: allergyErr } = await supabase
    .from('patient_allergies')
    .delete()
    .in('patient_id', demoAllergyPatientIds);

  if (allergyErr) {
    console.error('❌ Error cleaning patient_allergies:', allergyErr.message);
  } else {
    console.log('✅ Cleaned default patient_allergies.');
  }

  // 4. Purge patient_medications for default demo patients
  console.log('\n🗑️ Cleaning default patient_medications...');
  const demoMedPatientIds = [
    'PAT-2026-001',
    'usr_pat_PAT-2026-001',
    'usr_pat_001',
    'guest-patient',
    'patient-rag-test-1790849153246'
  ];
  const { error: medErr } = await supabase
    .from('patient_medications')
    .delete()
    .in('patient_id', demoMedPatientIds);

  if (medErr) {
    console.error('❌ Error cleaning patient_medications:', medErr.message);
  } else {
    console.log('✅ Cleaned default patient_medications.');
  }

  // 5. Verification
  console.log('\n📊 POST-CLEANUP STATUS:');
  const { data: remainingProfiles } = await supabase.from('profiles').select('id, full_name, email, role');
  console.log('--- REMAINING PROFILES ---');
  for (const p of remainingProfiles || []) {
    console.log(`[${p.role}] ${p.full_name} (${p.email})`);
  }

  const { data: remainingRosters } = await supabase.from('patient_rosters').select('patient_id, name, email');
  console.log('\n--- REMAINING PATIENT ROSTERS ---');
  for (const r of remainingRosters || []) {
    console.log(`${r.patient_id} - ${r.name || r.email}`);
  }

  const { count: allergyCount } = await supabase.from('patient_allergies').select('*', { count: 'exact', head: true });
  console.log(`\n--- REMAINING ALLERGIES: ${allergyCount ?? 0} rows ---`);

  const { count: medCount } = await supabase.from('patient_medications').select('*', { count: 'exact', head: true });
  console.log(`--- REMAINING MEDICATIONS: ${medCount ?? 0} rows ---`);

  process.exit(0);
}

deleteDefaultMockData().catch(console.error);
