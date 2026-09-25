import 'dotenv/config';
import { supabase } from '../src/config/supabase.js';

async function seed() {
  console.log('🌱 [Seeder] Seeding patient database records into Supabase...');

  const patientIds = [
    'usr_pat_PAT-2026-001',
    'PAT-2026-001',
    'usr_pat_001',
    'usr_pat_PAT-2026-002',
    'PAT-2026-002',
    'usr_pat_PAT-2026-003',
    'PAT-2026-003'
  ];

  // 1. Seed Patient Allergies
  console.log('🩺 Seeding patient_allergies...');
  const allergies = [
    {
      patient_id: 'PAT-2026-001',
      allergen_group: 'PENICILLINS',
      reaction_description: 'Severe Anaphylaxis, Bronchospasm & Facial Angioedema'
    },
    {
      patient_id: 'usr_pat_PAT-2026-001',
      allergen_group: 'PENICILLINS',
      reaction_description: 'Severe Anaphylaxis, Bronchospasm & Facial Angioedema'
    },
    {
      patient_id: 'usr_pat_001',
      allergen_group: 'PENICILLINS',
      reaction_description: 'Severe Anaphylaxis, Bronchospasm & Facial Angioedema'
    },
    {
      patient_id: 'PAT-2026-001',
      allergen_group: 'NSAIDS',
      reaction_description: 'Urticaria, Gastric Distress & Dyspnea'
    },
    {
      patient_id: 'usr_pat_PAT-2026-001',
      allergen_group: 'NSAIDS',
      reaction_description: 'Urticaria, Gastric Distress & Dyspnea'
    },
    {
      patient_id: 'usr_pat_001',
      allergen_group: 'NSAIDS',
      reaction_description: 'Urticaria, Gastric Distress & Dyspnea'
    },
    {
      patient_id: 'PAT-2026-002',
      allergen_group: 'SULFONAMIDES',
      reaction_description: 'Erythema Multiforme & Contact Dermatitis'
    }
  ];

  for (const a of allergies) {
    const { error } = await supabase.from('patient_allergies').insert([a]);
    if (error) console.warn('Allergy insert notice:', error.message);
  }

  // 2. Seed Patient Medications
  console.log('💊 Seeding patient_medications...');
  const medications = [
    {
      patient_id: 'PAT-2026-001',
      medication_name: 'Lipitor (Atorvastatin Calcium)',
      active_ingredient: 'Atorvastatin',
      dosage: '20mg • Oral Tablet (Once daily at bedtime)',
      is_active: true
    },
    {
      patient_id: 'usr_pat_PAT-2026-001',
      medication_name: 'Lipitor (Atorvastatin Calcium)',
      active_ingredient: 'Atorvastatin',
      dosage: '20mg • Oral Tablet (Once daily at bedtime)',
      is_active: true
    },
    {
      patient_id: 'usr_pat_001',
      medication_name: 'Lipitor (Atorvastatin Calcium)',
      active_ingredient: 'Atorvastatin',
      dosage: '20mg • Oral Tablet (Once daily at bedtime)',
      is_active: true
    },
    {
      patient_id: 'PAT-2026-001',
      medication_name: 'Glucophage (Metformin Hydrochloride)',
      active_ingredient: 'Metformin',
      dosage: '500mg • Extended Release (Twice daily with meals)',
      is_active: true
    },
    {
      patient_id: 'usr_pat_PAT-2026-001',
      medication_name: 'Glucophage (Metformin Hydrochloride)',
      active_ingredient: 'Metformin',
      dosage: '500mg • Extended Release (Twice daily with meals)',
      is_active: true
    },
    {
      patient_id: 'usr_pat_001',
      medication_name: 'Glucophage (Metformin Hydrochloride)',
      active_ingredient: 'Metformin',
      dosage: '500mg • Extended Release (Twice daily with meals)',
      is_active: true
    },
    {
      patient_id: 'PAT-2026-001',
      medication_name: 'Ventolin HFA (Albuterol Sulfate)',
      active_ingredient: 'Albuterol',
      dosage: '90mcg Inhalation Aerosol (1-2 puffs q4-6h PRN)',
      is_active: true
    },
    {
      patient_id: 'usr_pat_PAT-2026-001',
      medication_name: 'Ventolin HFA (Albuterol Sulfate)',
      active_ingredient: 'Albuterol',
      dosage: '90mcg Inhalation Aerosol (1-2 puffs q4-6h PRN)',
      is_active: true
    },
    {
      patient_id: 'usr_pat_001',
      medication_name: 'Ventolin HFA (Albuterol Sulfate)',
      active_ingredient: 'Albuterol',
      dosage: '90mcg Inhalation Aerosol (1-2 puffs q4-6h PRN)',
      is_active: true
    }
  ];

  for (const m of medications) {
    const { error } = await supabase.from('patient_medications').insert([m]);
    if (error) console.warn('Medication insert notice:', error.message);
  }

  // 3. Seed Health Screenings (Chronological Longitudinal Progression)
  console.log('📈 Seeding health_screenings...');
  const screenings = [
    // Baseline Screening (T0 - 14 days ago)
    {
      patient_id: 'PAT-2026-001',
      institution_id: 'nano123',
      multimodal_risk_score: 0.74,
      risk_level: 'HIGH',
      status: 'COMPLETED',
      symptom_payload: {
        symptoms: ['High persistent fever', 'Deep spasmodic cough', 'Shortness of breath on exertion'],
        bodyLocation: 'Chest / Lower Respiratory',
        durationDays: 5,
        painScale: 6,
        vitals: { heartRate: 104, spo2: 93, temperatureCelsius: 38.8 }
      },
      uncertainty_bounds: { min: 0.68, max: 0.81 },
      clinical_findings: [
        { condition: 'Acute Infectious Bronchitis', code: 'CA20', confidence: 0.89, category: 'Respiratory' },
        { condition: 'Atypical Bacterial Pneumonitis', code: 'CA40', confidence: 0.76, category: 'Pulmonary' }
      ],
      created_at: new Date(Date.now() - 14 * 86400000).toISOString()
    },
    // Follow-up Screening (T1 - 7 days ago)
    {
      patient_id: 'PAT-2026-001',
      institution_id: 'nano123',
      multimodal_risk_score: 0.46,
      risk_level: 'MODERATE',
      status: 'COMPLETED',
      symptom_payload: {
        symptoms: ['Mild productive cough', 'Resolving low-grade fever'],
        bodyLocation: 'Chest / Respiratory',
        durationDays: 3,
        painScale: 3,
        vitals: { heartRate: 88, spo2: 96, temperatureCelsius: 37.4 }
      },
      uncertainty_bounds: { min: 0.40, max: 0.52 },
      clinical_findings: [
        { condition: 'Convalescent Bronchial Inflammation', code: 'CA20.1', confidence: 0.82, category: 'Respiratory' }
      ],
      created_at: new Date(Date.now() - 7 * 86400000).toISOString()
    },
    // Current Screening (T2 - Yesterday)
    {
      patient_id: 'PAT-2026-001',
      institution_id: 'nano123',
      multimodal_risk_score: 0.18,
      risk_level: 'LOW',
      status: 'COMPLETED',
      symptom_payload: {
        symptoms: ['Trace dry throat clearing', 'Normal pulmonary stamina'],
        bodyLocation: 'Upper Respiratory',
        durationDays: 1,
        painScale: 0,
        vitals: { heartRate: 74, spo2: 99, temperatureCelsius: 36.7 }
      },
      uncertainty_bounds: { min: 0.12, max: 0.24 },
      clinical_findings: [
        { condition: 'Resolved Upper Respiratory Tract Infection', code: 'CA01', confidence: 0.94, category: 'Respiratory' }
      ],
      created_at: new Date(Date.now() - 1 * 86400000).toISOString()
    }
  ];

  // Also duplicate for usr_pat_PAT-2026-001 and usr_pat_001
  for (const s of screenings) {
    await supabase.from('health_screenings').insert([s]);
    await supabase.from('health_screenings').insert([{ ...s, patient_id: 'usr_pat_PAT-2026-001' }]);
    await supabase.from('health_screenings').insert([{ ...s, patient_id: 'usr_pat_001' }]);
  }

  console.log('✅ Seeding completed successfully!');
  process.exit(0);
}

seed().catch(err => {
  console.error('Seeding error:', err);
  process.exit(1);
});
