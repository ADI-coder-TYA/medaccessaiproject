import 'dotenv/config';
import { supabase } from '../src/config/supabase.js';

async function listProfiles() {
  const { data: profiles, error } = await supabase.from('profiles').select('*');
  console.log('Profiles in Supabase:', error ? error.message : profiles);

  const { data: rosters } = await supabase.from('patient_rosters').select('*');
  console.log('Patient Rosters in Supabase:', rosters);

  process.exit(0);
}

listProfiles();
