import 'dotenv/config';
import { supabase } from '../src/config/supabase.js';

async function inspect() {
  const tables = [
    'health_screenings',
    'patient_medications',
    'patient_allergies',
    'prescription_scans',
    'emergency_facilities',
    'claims',
    'profiles'
  ];

  for (const table of tables) {
    const { data, error } = await supabase.from(table).select('*').limit(3);
    if (error) {
      console.log(`❌ [${table}]:`, error.message);
    } else {
      console.log(`✅ [${table}] exists! Count:`, data.length);
      if (data.length > 0) {
        console.log(`   Sample keys:`, Object.keys(data[0]));
      }
    }
  }

  process.exit(0);
}

inspect();
