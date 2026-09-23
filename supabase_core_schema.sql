-- 0. Institutions Table (Multi-Tenancy)
create table if not exists public.institutions (
    id text primary key,
    name text not null,
    domain text,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 0b. Student Whitelist Rosters Table
create table if not exists public.student_rosters (
    id uuid primary key default gen_random_uuid(),
    institution_id text not null references public.institutions(id) on delete cascade,
    email text,
    student_id text,
    phone text,
    is_registered boolean default false,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.institutions enable row level security;
alter table public.student_rosters enable row level security;
create policy "Enable full access for service_role on institutions" on public.institutions for all to service_role using (true) with check (true);
create policy "Enable full access for service_role on student_rosters" on public.student_rosters for all to service_role using (true) with check (true);
create index if not exists student_rosters_email_idx on public.student_rosters (email);
create index if not exists student_rosters_phone_idx on public.student_rosters (phone);
create index if not exists student_rosters_inst_idx on public.student_rosters (institution_id);

-- 0c. Profiles / Users Table (Auth & RBAC)
create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    email text not null,
    role text not null check (role in ('STUDENT', 'ADMIN', 'AUDITOR')),
    institution_id text not null references public.institutions(id),
    phone text,
    name text,
    avatar_url text,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.profiles enable row level security;
create policy "Enable full access for service_role on profiles" on public.profiles for all to service_role using (true) with check (true);
create index if not exists profiles_email_idx on public.profiles (email);
create index if not exists profiles_role_idx on public.profiles (role);

-- 1. Students Table
create table if not exists public.students (
    id uuid primary key default gen_random_uuid(),
    institution_id text not null,
    phone text,
    name text,
    email text,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 2. Tickets Table
create table if not exists public.tickets (
    id uuid primary key default gen_random_uuid(),
    institution_id text not null,
    student_id uuid references public.students(id),
    student_phone text not null,
    raw_message text not null,
    media_url text,
    parsed_category text not null,
    urgency_level text not null default 'Routine',
    status text not null default 'Pending',
    calculated_amount numeric not null default 0.0,
    policy_match_reason text,
    flag_reason text,
    resolved_at timestamp with time zone,
    
    -- ML & AI Metrics
    dropout_risk_score numeric default 0.0,
    recommended_grant_amount numeric,
    grant_confidence_score numeric,
    model_variance numeric,
    crisis_severity_index numeric default 0.0,
    sentiment_negative_score numeric default 0.0,
    multi_department_involvement numeric default 0.0,
    policy_ambiguity_score numeric default 0.0,
    anomaly_reconstruction_score numeric,
    receipt_image_hash text,
    thought_process text,
    matched_policy_name text,

    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 3. Audit Logs Table
create table if not exists public.audit_logs (
    id uuid primary key default gen_random_uuid(),
    institution_id text not null,
    ticket_id uuid references public.tickets(id),
    action_type text not null,
    actor_type text not null,
    details jsonb,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 4. Funds Table
create table if not exists public.funds (
    id uuid primary key default gen_random_uuid(),
    institution_id text not null,
    fund_name text not null,
    total_budget numeric not null default 0.0,
    allocated_amount numeric not null default 0.0,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 5. Vouchers Table
create table if not exists public.vouchers (
    id uuid primary key default gen_random_uuid(),
    institution_id text not null,
    ticket_id uuid references public.tickets(id),
    voucher_code text not null,
    amount numeric not null,
    status text not null default 'Active',
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 6. Ticket Messages Table (Multi-turn Crisis Chat)
create table if not exists public.ticket_messages (
    id uuid primary key default gen_random_uuid(),
    ticket_id uuid not null references public.tickets(id) on delete cascade,
    sender text not null check (sender in ('STUDENT', 'COUNSELOR_AI', 'HUMAN_ADMIN')),
    message text not null,
    is_crisis_response boolean default false,
    suggested_resources jsonb,
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Enable RLS for all tables
alter table public.students enable row level security;
alter table public.tickets enable row level security;
alter table public.audit_logs enable row level security;
alter table public.funds enable row level security;
alter table public.vouchers enable row level security;
alter table public.ticket_messages enable row level security;

-- Create service_role bypass policies for backend access
create policy "Enable full access for service_role on students" on public.students for all to service_role using (true) with check (true);
create policy "Enable full access for service_role on tickets" on public.tickets for all to service_role using (true) with check (true);
create policy "Enable full access for service_role on audit_logs" on public.audit_logs for all to service_role using (true) with check (true);
create policy "Enable full access for service_role on funds" on public.funds for all to service_role using (true) with check (true);
create policy "Enable full access for service_role on vouchers" on public.vouchers for all to service_role using (true) with check (true);
create policy "Enable full access for service_role on ticket_messages" on public.ticket_messages for all to service_role using (true) with check (true);

-- Create indexes for common lookup paths
create index if not exists tickets_institution_id_idx on public.tickets (institution_id);
create index if not exists audit_logs_ticket_id_idx on public.audit_logs (ticket_id);
create index if not exists students_phone_idx on public.students (phone);
create index if not exists ticket_messages_ticket_id_idx on public.ticket_messages (ticket_id);
create index if not exists ticket_messages_created_at_idx on public.ticket_messages (created_at);

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO service_role;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- Added for Semantic Search, Fraud Sentinel & Disbursements
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS embedding vector(768);
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS receipt_image_hash text;
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS fraud_risk_score double precision default 0.0;
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS fraud_flags text;
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS payout_reference text;
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS payout_method text;
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS institution_id text default 'edu-admin-123';
ALTER TABLE public.tickets ADD COLUMN IF NOT EXISTS currency text default 'INR';
ALTER TABLE public.funds ADD COLUMN IF NOT EXISTS currency text default 'INR';
ALTER TABLE public.institutions ADD COLUMN IF NOT EXISTS currency text default 'INR';

-- 7. Health Screenings Table (Clinical Multimodal Diagnostics)
CREATE TABLE IF NOT EXISTS public.health_screenings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id UUID REFERENCES public.students(id) ON DELETE CASCADE,
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

ALTER TABLE public.health_screenings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Enable full access for service_role on health_screenings" ON public.health_screenings FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "Patients can view their own health screenings" ON public.health_screenings FOR SELECT TO authenticated USING (patient_id = auth.uid());
CREATE INDEX IF NOT EXISTS health_screenings_patient_id_idx ON public.health_screenings (patient_id);
CREATE INDEX IF NOT EXISTS health_screenings_institution_id_idx ON public.health_screenings (institution_id);
CREATE INDEX IF NOT EXISTS health_screenings_created_at_idx ON public.health_screenings (created_at DESC);
GRANT ALL PRIVILEGES ON TABLE public.health_screenings TO service_role;

