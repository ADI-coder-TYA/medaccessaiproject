import 'dotenv/config';
import { supabase } from '../src/config/supabase.js';

async function main() {
  const { data: profs } = await supabase.from('profiles').select('id, full_name, email, role, institution_id');
  console.log('--- PROFILES ---');
  for (const p of profs || []) {
    console.log(`[${p.role}] id: ${p.id} | name: ${p.full_name} | email: ${p.email} | inst: ${p.institution_id}`);
  }

  const { data: rosters } = await supabase.from('patient_rosters').select('*');
  console.log('\n--- PATIENT_ROSTERS ---');
  for (const r of rosters || []) {
    console.log(r);
  }

  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
