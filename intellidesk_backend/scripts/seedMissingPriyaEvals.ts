import 'dotenv/config';
import { supabase } from './dist/src/config/supabase.js';
import { CDSSService } from './dist/src/modules/cdss/CDSSService.js';

async function main() {
  console.log('=== SEEDING MISSING EVALS FOR PRIYA SHARMA ===');
  const missingIds = [
    '4d9ddd78-b853-4b3c-88f7-12fdc7e4f752',
    '17ded0d5-7e6e-437b-abd3-22c43db41694'
  ];

  for (const id of missingIds) {
    const { data: sc } = await supabase.from('health_screenings').select('*').eq('id', id).single();
    if (sc) {
      console.log(`Evaluating for screening ${id}...`);
      const evalResult = await CDSSService.evaluateScreening({
        screeningId: sc.id,
        patientId: 'usr_pat_PAT-2026-002',
        institutionId: 'nano123',
        multimodalRiskScore: sc.multimodal_risk_score ?? 0.5,
        symptoms: sc.symptom_payload || {},
        visionFindings: sc.clinical_findings || [],
        useCloudModel: false // Use local model to avoid cloud delay
      });
      console.log(`Saved eval ${evalResult.id} for screening ${id}`);
    }
  }

  console.log('✅ Done!');
  process.exit(0);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
