import 'dotenv/config';
import { supabase } from '../src/config/supabase.js';

async function testInsert() {
  // Test patient_allergies
  const { data: algData, error: algError } = await supabase.from('patient_allergies').insert([{
    patient_id: 'usr_pat_PAT-2026-001',
    allergen_group: 'PENICILLINS',
    reaction_description: 'Severe Anaphylaxis / Bronchospasm'
  }]).select();
  console.log('Insert patient_allergies:', algError ? algError.message : algData);

  // Test patient_medications
  const { data: medData, error: medError } = await supabase.from('patient_medications').insert([{
    patient_id: 'usr_pat_PAT-2026-001',
    medication_name: 'Lipitor (Atorvastatin)',
    active_ingredient: 'Atorvastatin',
    dosage: '20mg • Oral Tablet',
    is_active: true
  }]).select();
  console.log('Insert patient_medications:', medError ? medError.message : medData);

  // Test health_screenings
  const { data: hsData, error: hsError } = await supabase.from('health_screenings').insert([{
    patient_id: 'usr_pat_PAT-2026-001',
    institution_id: 'inst-001',
    multimodal_risk_score: 0.65,
    risk_level: 'Moderate',
    status: 'COMPLETED',
    symptom_payload: {
      symptoms: ['Cough', 'Low-grade fever', 'Sore throat'],
      bodyLocation: 'Chest / Respiratory',
      durationDays: 3,
      painScale: 2
    },
    uncertainty_bounds: { min: 0.58, max: 0.72 },
    clinical_findings: [
      { condition: 'Acute Bronchitis & Pulmonary Congestion', code: 'CA20', confidence: 0.88, category: 'Respiratory' }
    ]
  }]).select();
  console.log('Insert health_screenings:', hsError ? hsError.message : hsData);

  process.exit(0);
}

testInsert();
