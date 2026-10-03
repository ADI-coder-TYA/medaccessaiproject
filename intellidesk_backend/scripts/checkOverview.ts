import 'dotenv/config';
import { HealthScreeningsDbService } from './dist/src/modules/diagnostics/db/healthScreeningsDbService.js';

async function main() {
  console.log('=== CALLING getAdminPatientsOverview("nano123") ===');
  const overview = await HealthScreeningsDbService.getAdminPatientsOverview('nano123');
  console.log('Total overview patients:', overview.length);
  for (const p of overview) {
    console.log({
      patientId: p.patientId,
      canonicalPatientId: p.canonicalPatientId,
      patientName: p.patientName,
      totalDiagnoses: p.totalDiagnoses,
      screeningsCount: p.screenings?.length,
      sampleScreeningPatientIds: p.screenings?.map((s: any) => s.patient_id).slice(0, 3)
    });
  }
  process.exit(0);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
