-- Migration: 20260923000000_health_screenings.sql
-- Description: Health screenings table for clinical multimodal diagnostics subsystem

CREATE TABLE IF NOT EXISTS public.health_screenings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id TEXT,
    previous_screening_id UUID REFERENCES public.health_screenings(id) ON DELETE SET NULL,
    institution_id TEXT NOT NULL DEFAULT 'edu-admin-123',
    image_url TEXT,
    symptom_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    multimodal_risk_score DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    uncertainty_bounds JSONB NOT NULL DEFAULT '{"confidence": 0.0, "ci_lower": 0.0, "ci_upper": 0.0, "epistemic_variance": 0.0}'::jsonb,
    xai_heatmap_url TEXT,
    clinical_findings JSONB DEFAULT '[]'::jsonb,
    risk_level TEXT NOT NULL DEFAULT 'LOW',
    status TEXT NOT NULL DEFAULT 'COMPLETED',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Enable Row Level Security
ALTER TABLE public.health_screenings ENABLE ROW LEVEL SECURITY;

-- Service Role Policy
CREATE POLICY "Enable full access for service_role on health_screenings" 
ON public.health_screenings 
FOR ALL 
TO service_role 
USING (true) 
WITH CHECK (true);

-- Authenticated User Policy (Patients read their own screenings)
CREATE POLICY "Patients can view their own health screenings" 
ON public.health_screenings 
FOR SELECT 
TO authenticated 
USING (patient_id = auth.uid()::text);

-- Indexes for performant lookups
CREATE INDEX IF NOT EXISTS health_screenings_patient_id_idx ON public.health_screenings (patient_id);
CREATE INDEX IF NOT EXISTS health_screenings_prev_screening_id_idx ON public.health_screenings (previous_screening_id);
CREATE INDEX IF NOT EXISTS health_screenings_institution_id_idx ON public.health_screenings (institution_id);
CREATE INDEX IF NOT EXISTS health_screenings_created_at_idx ON public.health_screenings (created_at DESC);
CREATE INDEX IF NOT EXISTS health_screenings_risk_level_idx ON public.health_screenings (risk_level);

GRANT ALL PRIVILEGES ON TABLE public.health_screenings TO service_role;
