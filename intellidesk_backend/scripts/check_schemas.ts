import 'dotenv/config';
import { supabase } from '../src/config/supabase.js';

async function checkColumns() {
  // Let's check RPC or columns from Postgres information_schema
  const { data, error } = await supabase.rpc('get_schema_info');
  if (error) {
    // If no RPC, let's query with an empty select or invalid column to get column names in error message
    console.log('No get_schema_info RPC. Testing tables by querying columns:');
    for (const tbl of ['patient_medications', 'patient_allergies', 'health_screenings', 'prescription_scans']) {
      const res = await supabase.from(tbl).select('*').limit(1);
      console.log(`Table ${tbl}:`, res.error ? res.error.message : 'OK query');
    }
  } else {
    console.log('Schema info:', data);
  }

  process.exit(0);
}

checkColumns();
