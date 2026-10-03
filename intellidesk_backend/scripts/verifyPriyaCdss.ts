import 'dotenv/config';
import { CDSSService } from './dist/src/modules/cdss/CDSSService.js';
import { HealthScreeningsDbService } from './dist/src/modules/diagnostics/db/healthScreeningsDbService.js';

async function main() {
  console.log('=== VERIFYING PRIYA SHARMA CDSS RETRIEVAL ===');
  const screenings = await HealthScreeningsDbService.getScreeningsByPatient('usr_pat_PAT-2026-002');
  console.log(`Found ${screenings.length} screenings for Priya Sharma`);

  let successCount = 0;
  for (const s of screenings) {
    const hasInline = !!s.cdss_evaluation;
    const retrieved = await CDSSService.getEvaluationByScreeningId(s.id);
    const hasRetrieved = !!retrieved;
    const diffs = retrieved?.differentialDiagnoses?.length || s.cdss_evaluation?.differentialDiagnoses?.length;
    console.log(`Screening ${s.id} | Inline CDSS: ${hasInline} | Retrieved: ${hasRetrieved} | Differentials: ${diffs} | Primary: ${retrieved?.primaryICD11Code || s.cdss_evaluation?.primaryICD11Code}`);
    if (hasInline || hasRetrieved) successCount++;
  }

  console.log(`\n✅ Summary: ${successCount}/${screenings.length} screenings have valid CDSS evaluations!`);
  process.exit(0);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
