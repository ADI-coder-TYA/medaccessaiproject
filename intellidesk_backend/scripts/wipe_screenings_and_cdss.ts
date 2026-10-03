import 'dotenv/config';
import { supabase } from '../src/config/supabase.js';

async function wipeScreeningsAndCdss() {
  console.log('🧹 [Database Purge] Wiping all health screenings and CDSS evaluations from Supabase...');

  // 1. Check current counts
  const { count: cdssCountBefore } = await supabase
    .from('cdss_evaluations')
    .select('*', { count: 'exact', head: true });

  const { count: screeningsCountBefore } = await supabase
    .from('health_screenings')
    .select('*', { count: 'exact', head: true });

  console.log(`📊 BEFORE PURGE:`);
  console.log(`   • cdss_evaluations : ${cdssCountBefore ?? 0} rows`);
  console.log(`   • health_screenings: ${screeningsCountBefore ?? 0} rows`);

  // 2. Delete cdss_evaluations first (foreign key reference to health_screenings)
  console.log('\n🗑️ Deleting all records from cdss_evaluations...');
  const { error: cdssError } = await supabase
    .from('cdss_evaluations')
    .delete()
    .neq('id', '00000000-0000-0000-0000-000000000000');

  if (cdssError) {
    console.error('❌ Error clearing cdss_evaluations:', cdssError.message);
  } else {
    console.log('✅ Successfully cleared cdss_evaluations.');
  }

  // 3. Delete health_screenings
  console.log('\n🗑️ Deleting all records from health_screenings...');
  const { error: hsError } = await supabase
    .from('health_screenings')
    .delete()
    .neq('id', '00000000-0000-0000-0000-000000000000');

  if (hsError) {
    console.error('❌ Error clearing health_screenings:', hsError.message);
  } else {
    console.log('✅ Successfully cleared health_screenings.');
  }

  // 4. Verify post-wipe counts
  const { count: cdssCountAfter } = await supabase
    .from('cdss_evaluations')
    .select('*', { count: 'exact', head: true });

  const { count: screeningsCountAfter } = await supabase
    .from('health_screenings')
    .select('*', { count: 'exact', head: true });

  console.log('\n📊 AFTER PURGE:');
  console.log(`   • cdss_evaluations : ${cdssCountAfter ?? 0} rows`);
  console.log(`   • health_screenings: ${screeningsCountAfter ?? 0} rows`);

  if ((cdssCountAfter ?? 0) === 0 && (screeningsCountAfter ?? 0) === 0) {
    console.log('\n🎉 SUCCESS: All screenings and CDSS evaluations have been cleanly wiped!');
  } else {
    console.warn('\n⚠️ WARNING: Some rows could not be deleted.');
  }

  process.exit(0);
}

wipeScreeningsAndCdss().catch((err) => {
  console.error('Fatal purge error:', err);
  process.exit(1);
});
