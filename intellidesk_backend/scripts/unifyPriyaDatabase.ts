import 'dotenv/config';
import { supabase } from './dist/src/config/supabase.js';

async function main() {
  console.log('=== UNIFYING PRIYA SHARMA DATABASE RECORDS ===');

  // 1. Check health_screenings with 9470
  const { data: scs, error: scErr } = await supabase
    .from('health_screenings')
    .select('id, patient_id, symptom_payload')
    .or('patient_id.eq.usr_pat_PAT-9470,patient_id.eq.PAT-9470');

  console.log('Found health_screenings to migrate:', scs?.length, 'error:', scErr?.message);

  if (scs && scs.length > 0) {
    const { data: updatedScs, error: uErr } = await supabase
      .from('health_screenings')
      .update({
        patient_id: 'usr_pat_PAT-2026-002',
        institution_id: 'nano123'
      })
      .or('patient_id.eq.usr_pat_PAT-9470,patient_id.eq.PAT-9470')
      .select('id, patient_id');

    console.log('Updated health_screenings count:', updatedScs?.length, 'error:', uErr?.message);
  }

  // 2. Check cdss_evaluations with 9470
  const { data: cdss, error: cdErr } = await supabase
    .from('cdss_evaluations')
    .select('id, patient_id, screening_id')
    .or('patient_id.eq.usr_pat_PAT-9470,patient_id.eq.PAT-9470');

  console.log('Found cdss_evaluations to migrate:', cdss?.length, 'error:', cdErr?.message);

  if (cdss && cdss.length > 0) {
    const { data: updatedCdss, error: ucErr } = await supabase
      .from('cdss_evaluations')
      .update({
        patient_id: 'usr_pat_PAT-2026-002'
      })
      .or('patient_id.eq.usr_pat_PAT-9470,patient_id.eq.PAT-9470')
      .select('id, patient_id');

    console.log('Updated cdss_evaluations count:', updatedCdss?.length, 'error:', ucErr?.message);
  }

  // 3. Verify total screenings for usr_pat_PAT-2026-002
  const { count: finalCount } = await supabase
    .from('health_screenings')
    .select('*', { count: 'exact', head: true })
    .eq('patient_id', 'usr_pat_PAT-2026-002');

  console.log(`✅ All Priya Sharma records unified! Total screenings for usr_pat_PAT-2026-002: ${finalCount}`);
  process.exit(0);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
