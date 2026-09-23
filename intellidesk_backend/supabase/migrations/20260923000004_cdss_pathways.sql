-- Migration: 20260923000004_cdss_pathways.sql
-- Description: Clinical Decision Support System (CDSS) knowledge base, DDx evaluations, and clinician provenance

-- 1. ICD-11 Clinical Knowledge Base
CREATE TABLE IF NOT EXISTS public.icd11_knowledge_base (
    code TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    category TEXT,
    uri_stem TEXT NOT NULL DEFAULT 'http://id.who.int/icd/release/11/mms',
    clinical_criteria JSONB NOT NULL DEFAULT '{}'::jsonb,
    first_line_pathway JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 2. CDSS Evaluations Table
CREATE TABLE IF NOT EXISTS public.cdss_evaluations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    screening_id UUID REFERENCES public.health_screenings(id) ON DELETE CASCADE,
    patient_id TEXT NOT NULL,
    primary_icd11_code TEXT NOT NULL,
    differential_diagnoses JSONB NOT NULL,
    treatment_pathway JSONB NOT NULL,
    regulatory_disclaimer TEXT NOT NULL,
    temperature_scaling NUMERIC(3,2) DEFAULT 1.25,
    attending_clinician_approval JSONB DEFAULT NULL,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Indices for performance
CREATE INDEX IF NOT EXISTS idx_cdss_screening_id ON public.cdss_evaluations(screening_id);
CREATE INDEX IF NOT EXISTS idx_cdss_patient_id ON public.cdss_evaluations(patient_id);
CREATE INDEX IF NOT EXISTS idx_icd11_category ON public.icd11_knowledge_base(category);

-- RLS Policies
ALTER TABLE public.icd11_knowledge_base ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cdss_evaluations ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    DROP POLICY IF EXISTS "Allow read icd11_knowledge_base for authenticated" ON public.icd11_knowledge_base;
    CREATE POLICY "Allow read icd11_knowledge_base for authenticated"
        ON public.icd11_knowledge_base FOR SELECT
        TO authenticated, anon
        USING (true);

    DROP POLICY IF EXISTS "Allow all for authenticated cdss_evaluations" ON public.cdss_evaluations;
    CREATE POLICY "Allow all for authenticated cdss_evaluations"
        ON public.cdss_evaluations FOR ALL
        TO authenticated, anon
        USING (true);
END $$;
