import 'dotenv/config';
import { supabase } from '../src/config/supabase.js';

async function listInst() {
  const { data: insts } = await supabase.from('institutions').select('*');
  console.log('INSTITUTIONS in DB:', insts);
  const { data: profs } = await supabase.from('profiles').select('id, email, full_name, role, institution_id');
  console.log('PROFILES in DB:', profs);
  const { data: rosters } = await supabase.from('patient_rosters').select('*').limit(10);
  console.log('PATIENT ROSTERS in DB:', rosters);
  process.exit(0);
}

listInst();
