-- Migration: 20260923000003_vitals_rppg.sql
-- Description: Touchless vital signs extraction via camera photoplethysmography (rPPG)

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'health_screenings') THEN
        ALTER TABLE public.health_screenings ADD COLUMN IF NOT EXISTS rppg_vitals_payload JSONB DEFAULT NULL;
        ALTER TABLE public.health_screenings ADD COLUMN IF NOT EXISTS physiological_alerts JSONB DEFAULT '[]'::jsonb;
    END IF;
END $$;
