import 'dotenv/config';
import { supabase } from './dist/src/config/supabase.js';

async function main() {
  console.log('=== ATTACHING CDSS TO HEALTH_SCREENINGS.SYMPTOM_PAYLOAD ===');
  const { data: screenings } = await supabase
    .from('health_screenings')
    .select('id, symptom_payload, cdss_evaluations(*)');

  let updated = 0;
  for (const s of screenings || []) {
    if (s.cdss_evaluations && s.cdss_evaluations.length > 0) {
      const evalData = s.cdss_evaluations[0];
      const payload = s.symptom_payload || {};
      payload.cdss_evaluation = {
        id: evalData.id,
        screeningId: evalData.screening_id || s.id,
        patientId: evalData.patient_id,
        primaryICD11Code: evalData.primary_icd11_code,
        primaryICD11Title: evalData.differential_diagnoses?.[0]?.title || evalData.primary_icd11_code,
        primaryICD11Uri: `http://id.who.int/icd/release/11/mms/${evalData.primary_icd11_code}`,
        differentialDiagnoses: evalData.differential_diagnoses || [],
        treatmentPathway: evalData.treatment_pathway,
        temperatureScaling: Number(evalData.temperature_scaling) || 1.25,
        regulatoryDisclaimer: evalData.regulatory_disclaimer,
        attendingClinicianApproval: evalData.attending_clinician_approval || null,
        createdAt: evalData.created_at,
        updatedAt: evalData.updated_at
      };

      await supabase
        .from('health_screenings')
        .update({ symptom_payload: payload })
        .eq('id', s.id);

      updated++;
    }
  }

  console.log(`✅ Attached CDSS to symptom_payload for ${updated} screenings in Supabase!`);
  process.exit(0);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
