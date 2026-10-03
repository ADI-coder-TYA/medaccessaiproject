import 'dotenv/config';
import { supabase } from './dist/src/config/supabase.js';

async function main() {
  console.log('=== SCANNING DATABASE FOR PRIYA SHARMA & PATIENT IDS ===');

  // 1. Search in patient_rosters
  console.log('\n--- 1. patient_rosters ---');
  const { data: rosters, error: rErr } = await supabase
    .from('patient_rosters')
    .select('*')
    .or('name.ilike.%Priya%,student_id.ilike.%2026-002%,patient_id.ilike.%2026-002%');
  console.log('patient_rosters count:', rosters?.length, 'error:', rErr?.message);
  if (rosters) {
    for (const r of rosters) {
      console.log('Roster row:', JSON.stringify(r));
    }
  }

  // 2. Search in profiles
  console.log('\n--- 2. profiles ---');
  const { data: profiles, error: pErr } = await supabase
    .from('profiles')
    .select('id, email, full_name, role, institution_id')
    .or('full_name.ilike.%Priya%,email.ilike.%priya%');
  console.log('profiles count:', profiles?.length, 'error:', pErr?.message);
  if (profiles) {
    for (const p of profiles) {
      console.log('Profile row:', JSON.stringify(p));
    }
  }

  console.log('\n--- 3. health_screenings (ALL ROWS) ---');
  const { data: allScreenings, error: asErr } = await supabase
    .from('health_screenings')
    .select('id, patient_id, institution_id, created_at, symptom_payload')
    .order('created_at', { ascending: false });
  console.log('Total health_screenings in DB:', allScreenings?.length, 'error:', asErr?.message);
  if (allScreenings) {
    for (const s of allScreenings) {
      const name = s.symptom_payload?.patient_name || s.symptom_payload?.patientName;
      console.log(`[Screening] ID: ${s.id} | patient_id: "${s.patient_id}" | nameInPayload: "${name}" | inst: "${s.institution_id}"`);
    }
  }

  // Also all distinct patient_ids in health_screenings
  const { data: allScreeningPids } = await supabase
    .from('health_screenings')
    .select('patient_id, created_at')
    .order('created_at', { ascending: false })
    .limit(50);
  console.log('\nRecent 50 screening patient_ids:', allScreeningPids?.map(x => x.patient_id));

  // 4. Search in cdss_evaluations
  console.log('\n--- 4. cdss_evaluations ---');
  const { data: cdssEvals, error: cErr } = await supabase
    .from('cdss_evaluations')
    .select('id, screening_id, patient_id, primary_icd11_code, created_at')
    .or('patient_id.ilike.%2026-002%,patient_id.ilike.%Priya%');
  console.log('cdss_evaluations count for 2026-002/Priya:', cdssEvals?.length, 'error:', cErr?.message);
  if (cdssEvals) {
    for (const c of cdssEvals) {
      console.log(`CDSS Eval ID: ${c.id}, screening_id: ${c.screening_id}, patient_id: "${c.patient_id}", code: ${c.primary_icd11_code}, created_at: ${c.created_at}`);
    }
  }

  // 5. Check all cdss_evaluations count
  const { data: allCdss, error: acErr } = await supabase
    .from('cdss_evaluations')
    .select('id, screening_id, patient_id, primary_icd11_code, created_at')
    .order('created_at', { ascending: false })
    .limit(20);
  console.log('\nRecent cdss_evaluations count:', allCdss?.length, 'error:', acErr?.message);
  if (allCdss) {
    for (const c of allCdss) {
      console.log(`CDSS Eval ID: ${c.id}, screening_id: ${c.screening_id}, patient_id: "${c.patient_id}", code: ${c.primary_icd11_code}`);
    }
  }

  process.exit(0);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
