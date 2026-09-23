-- Migration: 20260923000002_rx_sentinel.sql
-- Description: RxSentinel prescription parsing, active ingredient extraction, and drug-drug interaction (DDI) & allergy safety engine

-- 1. Patient Allergies Table
CREATE TABLE IF NOT EXISTS public.patient_allergies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id TEXT NOT NULL,
    allergen_group TEXT NOT NULL, -- e.g. 'PENICILLINS', 'NSAIDS', 'SULFA', 'OPIOIDS'
    reaction_description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 2. Patient Active Medications Table
CREATE TABLE IF NOT EXISTS public.patient_medications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id TEXT NOT NULL,
    medication_name TEXT NOT NULL,
    active_ingredient TEXT NOT NULL,
    dosage TEXT,
    is_active BOOLEAN DEFAULT true NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 3. Prescription Scans Table
CREATE TABLE IF NOT EXISTS public.prescription_scans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id TEXT,
    image_url TEXT,
    extracted_drugs JSONB NOT NULL DEFAULT '[]'::jsonb,
    ddi_warnings JSONB DEFAULT '[]'::jsonb,
    allergy_conflicts JSONB DEFAULT '[]'::jsonb,
    has_safety_conflict BOOLEAN DEFAULT false NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 4. Claims Table Safety Flag (Guardrail 3)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'claims') THEN
        ALTER TABLE public.claims ADD COLUMN IF NOT EXISTS requires_clinical_pharmacist_review BOOLEAN DEFAULT false;
    END IF;
END $$;

-- Enable RLS
ALTER TABLE public.patient_allergies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.patient_medications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prescription_scans ENABLE ROW LEVEL SECURITY;

-- Service Role Full Access Policies
CREATE POLICY "Enable full access for service_role on patient_allergies"
ON public.patient_allergies FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE POLICY "Enable full access for service_role on patient_medications"
ON public.patient_medications FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE POLICY "Enable full access for service_role on prescription_scans"
ON public.prescription_scans FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Guardrail 1: RLS Policy for TEXT Patient IDs (compare auth.jwt() sub or student_id)
CREATE POLICY "Patients can view and manage their own drug allergies"
ON public.patient_allergies
FOR ALL
TO authenticated
USING (
    patient_id = (auth.jwt() ->> 'sub') 
    OR patient_id = (auth.jwt() ->> 'student_id')
    OR patient_id = auth.uid()::text
)
WITH CHECK (
    patient_id = (auth.jwt() ->> 'sub') 
    OR patient_id = (auth.jwt() ->> 'student_id')
    OR patient_id = auth.uid()::text
);

CREATE POLICY "Patients can view and manage their active medications"
ON public.patient_medications
FOR ALL
TO authenticated
USING (
    patient_id = (auth.jwt() ->> 'sub') 
    OR patient_id = (auth.jwt() ->> 'student_id')
    OR patient_id = auth.uid()::text
)
WITH CHECK (
    patient_id = (auth.jwt() ->> 'sub') 
    OR patient_id = (auth.jwt() ->> 'student_id')
    OR patient_id = auth.uid()::text
);

CREATE POLICY "Patients can view their own prescription scans"
ON public.prescription_scans
FOR SELECT
TO authenticated
USING (
    patient_id = (auth.jwt() ->> 'sub') 
    OR patient_id = (auth.jwt() ->> 'student_id')
    OR patient_id = auth.uid()::text
);

-- Performance Indexes
CREATE INDEX IF NOT EXISTS patient_allergies_patient_id_idx ON public.patient_allergies (patient_id);
CREATE INDEX IF NOT EXISTS patient_allergies_allergen_group_idx ON public.patient_allergies (allergen_group);
CREATE INDEX IF NOT EXISTS patient_medications_patient_id_idx ON public.patient_medications (patient_id);
CREATE INDEX IF NOT EXISTS patient_medications_active_idx ON public.patient_medications (patient_id, is_active);
CREATE INDEX IF NOT EXISTS prescription_scans_patient_id_idx ON public.prescription_scans (patient_id);
CREATE INDEX IF NOT EXISTS prescription_scans_created_at_idx ON public.prescription_scans (created_at DESC);

GRANT ALL PRIVILEGES ON TABLE public.patient_allergies TO service_role;
GRANT ALL PRIVILEGES ON TABLE public.patient_medications TO service_role;
GRANT ALL PRIVILEGES ON TABLE public.prescription_scans TO service_role;
