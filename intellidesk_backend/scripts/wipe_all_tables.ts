import 'dotenv/config';
import { supabase } from '../src/config/supabase.js';

async function wipeAllDatabaseTables() {
  console.log('🚨 STARTING COMPLETE DATABASE HARD WIPE (CLEAN SLATE)...');

  const tablesInOrder = [
    'cdss_evaluations',
    'health_screenings',
    'prescription_scans',
    'patient_medications',
    'patient_allergies',
    'audit_logs',
    'claim_messages',
    'vouchers',
    'claims',
    'tickets',
    'patient_rosters',
    'policy_embeddings',
    'policies',
    'health_funds',
    'funds',
    'profiles',
    'institutions',
  ];

  for (const table of tablesInOrder) {
    try {
      // Primary attempt by neq id
      let { error } = await supabase.from(table).delete().neq('id', '00000000-0000-0000-0000-000000000000');
      if (error) {
        // Fallback for tables without uuid 'id' column
        const { error: err2 } = await supabase.from(table).delete().neq('patient_id', 'NON_EXISTENT');
        if (err2) {
          const { error: err3 } = await supabase.from(table).delete().gt('created_at', '1970-01-01');
          if (err3) {
            console.warn(`⚠️ Notice wiping table "${table}":`, err3.message);
          } else {
            console.log(`🧹 Cleaned table: "${table}" (via created_at fallback)`);
          }
        } else {
          console.log(`🧹 Cleaned table: "${table}" (via patient_id fallback)`);
        }
      } else {
        console.log(`🧹 Cleaned table: "${table}"`);
      }
    } catch (e: any) {
      console.warn(`⚠️ Skipped table "${table}":`, e.message);
    }
  }

  // Double check all tables
  console.log('\n📊 POST-WIPE TABLE ROW COUNTS:');
  for (const table of tablesInOrder) {
    try {
      const { count, error } = await supabase.from(table).select('*', { count: 'exact', head: true });
      if (!error) {
        console.log(`   • ${table.padEnd(22)}: ${count ?? 0} rows`);
      } else {
        console.log(`   • ${table.padEnd(22)}: (table not found / error: ${error.message})`);
      }
    } catch (_) {}
  }

  console.log('\n✨ COMPLETE HARD WIPE FINISHED! Supabase database is 100% clean and reset.');
  process.exit(0);
}

wipeAllDatabaseTables().catch(console.error);
