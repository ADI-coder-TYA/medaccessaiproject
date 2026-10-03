import 'dotenv/config';
import { supabase } from './dist/src/config/supabase.js';

async function main() {
  console.log('=== CHECKING usr_pat_PAT-9470 SCREENINGS ===');
  const { data } = await supabase
    .from('health_screenings')
    .select('*')
    .eq('patient_id', 'usr_pat_PAT-9470');

  console.log('Count:', data?.length);
  for (const s of data || []) {
    console.log({
      id: s.id,
      patient_id: s.patient_id,
      created_at: s.created_at,
      symptom_payload: s.symptom_payload,
      clinical_findings: s.clinical_findings,
      institution_id: s.institution_id
    });
  }
  process.exit(0);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
