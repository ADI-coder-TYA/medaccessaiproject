import 'dotenv/config';
import { supabase } from '../src/config/supabase.js';

async function scanTables() {
  const tables = [
    'profiles',
    'patient_rosters',
    'patient_allergies',
    'patient_medications',
    'claims',
    'claim_messages',
    'vouchers',
    'tickets',
    'audit_logs',
    'prescriptions',
    'prescription_scans'
  ];

  console.log('🔍 SCANNING TABLES FOR DEFAULT MOCK DATA...');

  for (const t of tables) {
    try {
      const { data, error } = await supabase.from(t).select('*');
      if (error) {
        console.log(`Table ${t}: (error: ${error.message})`);
        continue;
      }
      if (!data || data.length === 0) {
        console.log(`Table ${t}: 0 rows`);
        continue;
      }

      const str = JSON.stringify(data).toLowerCase();
      const hasAlex = str.includes('alex') || str.includes('rivera');
      const hasMaya = str.includes('maya');
      const hasSarah = str.includes('sarah') || str.includes('chen');
      const has001 = str.includes('pat-2026-001') || str.includes('usr_pat_001');

      console.log(`Table ${t} (${data.length} rows): alex=${hasAlex}, maya=${hasMaya}, sarah=${hasSarah}, pat001=${has001}`);
    } catch (e: any) {
      console.log(`Table ${t}: exception ${e.message}`);
    }
  }

  process.exit(0);
}

scanTables().catch(console.error);
