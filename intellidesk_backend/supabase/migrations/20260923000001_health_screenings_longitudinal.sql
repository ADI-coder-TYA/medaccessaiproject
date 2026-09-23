-- Migration: 20260923000001_health_screenings_longitudinal.sql
-- Description: Adds previous_screening_id self-referencing foreign key for longitudinal screening progression tracking

ALTER TABLE public.health_screenings 
ADD COLUMN IF NOT EXISTS previous_screening_id UUID REFERENCES public.health_screenings(id) ON DELETE SET NULL;

-- Index for performant historical tree/chain lookups
CREATE INDEX IF NOT EXISTS health_screenings_prev_screening_id_idx 
ON public.health_screenings (previous_screening_id);
