-- ============================================================
-- Supabase Core Schema & Seed file for StranX Portal
-- Run this completely in the Supabase SQL Editor.
-- ============================================================

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. ENUMS
CREATE TYPE user_role AS ENUM ('super_admin', 'wfm_manager', 'database', 'scrubbing', 'tv', 'qc', 'delivery');
CREATE TYPE notification_type AS ENUM ('info', 'alert', 'sla_breach');

-- 3. TABLES

-- Roles Mapping Table
CREATE TABLE IF NOT EXISTS public.user_roles (
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    role user_role NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Allowed IPs
CREATE TABLE IF NOT EXISTS public.allowed_ips (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ip_address INET NOT NULL UNIQUE,
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Notifications
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    target_role user_role, -- NULL means broadcast
    message TEXT NOT NULL,
    type notification_type DEFAULT 'info',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Audit Logs
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    table_affected TEXT NOT NULL,
    record_id UUID,
    timestamp TIMESTAMPTZ DEFAULT NOW()
);

-- Lead Pipeline Tables

-- Database Team (Projects)
CREATE TABLE IF NOT EXISTS public.projects (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    project_name TEXT NOT NULL,
    did TEXT,
    target_count INTEGER DEFAULT 0,
    batch_1_count INTEGER DEFAULT 0,
    batch_2_count INTEGER DEFAULT 0,
    batch_3_count INTEGER DEFAULT 0,
    batch_4_count INTEGER DEFAULT 0,
    batch_5_count INTEGER DEFAULT 0,
    source TEXT,
    comments TEXT,
    created_by UUID REFERENCES auth.users(id),
    upload_timestamp TIMESTAMPTZ DEFAULT NOW()
);

-- Scrubbing Team
CREATE TABLE IF NOT EXISTS public.scrubbing_data (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    linked_project_id UUID REFERENCES public.projects(id) ON DELETE CASCADE,
    total_received INTEGER DEFAULT 0,
    accepted INTEGER DEFAULT 0,
    rejected INTEGER DEFAULT 0,
    qualification_status TEXT,
    comments TEXT,
    processed_by UUID REFERENCES auth.users(id),
    processed_timestamp TIMESTAMPTZ DEFAULT NOW()
);

-- TV (Tele-verification) Team
CREATE TABLE IF NOT EXISTS public.tv_data (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    linked_project_id UUID REFERENCES public.projects(id) ON DELETE CASCADE,
    total_called INTEGER DEFAULT 0,
    interested INTEGER DEFAULT 0,
    not_interested INTEGER DEFAULT 0,
    callback INTEGER DEFAULT 0,
    no_response INTEGER DEFAULT 0,
    verified_count INTEGER DEFAULT 0,
    comments TEXT,
    processed_by UUID REFERENCES auth.users(id),
    tv_timestamp TIMESTAMPTZ DEFAULT NOW()
);

-- Scrub QC Team
CREATE TABLE IF NOT EXISTS public.qc_data (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    linked_project_id UUID REFERENCES public.projects(id) ON DELETE CASCADE,
    email_received_time TIMESTAMPTZ,
    qc_status TEXT CHECK (qc_status IN ('Pending', 'WIP', 'Completed')) DEFAULT 'Pending',
    priority TEXT CHECK (priority IN ('Low', 'Medium', 'High')) DEFAULT 'Medium',
    total_count INTEGER DEFAULT 0,
    accepted_count INTEGER DEFAULT 0,
    rejected_count INTEGER DEFAULT 0,
    comments TEXT,
    processed_by UUID REFERENCES auth.users(id),
    qc_timestamp TIMESTAMPTZ DEFAULT NOW()
);

-- Delivery Team
CREATE TABLE IF NOT EXISTS public.delivery_data (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    linked_project_id UUID REFERENCES public.projects(id) ON DELETE CASCADE,
    final_delivered INTEGER DEFAULT 0,
    rejected INTEGER DEFAULT 0,
    rejection_percentage NUMERIC(5,2) GENERATED ALWAYS AS (
        CASE WHEN (final_delivered + rejected) > 0 
        THEN (rejected::NUMERIC / (final_delivered + rejected) * 100)
        ELSE 0 END
    ) STORED,
    comments TEXT,
    processed_by UUID REFERENCES auth.users(id),
    delivery_timestamp TIMESTAMPTZ DEFAULT NOW()
);

-- 4. ROW LEVEL SECURITY (RLS)
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.allowed_ips ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scrubbing_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tv_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.qc_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_data ENABLE ROW LEVEL SECURITY;

-- Helper to check if current user has role
CREATE OR REPLACE FUNCTION public.has_role(req_role user_role) RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = auth.uid() AND role = req_role
  );
$$ LANGUAGE sql SECURITY DEFINER;

-- RLS: user_roles
CREATE POLICY "Users can read own role" ON public.user_roles FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Super Admins can manage roles" ON public.user_roles FOR ALL USING (public.has_role('super_admin'));

-- RLS: allowed_ips
CREATE POLICY "Anyone can read IPs (for middleware)" ON public.allowed_ips FOR SELECT USING (true);
CREATE POLICY "Super Admins manage IPs" ON public.allowed_ips FOR ALL USING (public.has_role('super_admin'));

-- RLS: notifications
CREATE POLICY "Users see broadcast or target role notifications" ON public.notifications FOR SELECT USING (
  target_role IS NULL OR 
  public.has_role(target_role) OR 
  public.has_role('super_admin')
);
CREATE POLICY "Super Admins manage notifications" ON public.notifications FOR ALL USING (public.has_role('super_admin'));

-- RLS: audit_logs
CREATE POLICY "Super Admin and WFM manager can read audit logs" ON public.audit_logs FOR SELECT USING (
  public.has_role('super_admin') OR public.has_role('wfm_manager')
);
CREATE POLICY "Authenticated users can insert audit logs" ON public.audit_logs FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- RLS: Pipeline (simplified for space: wfm/admin full read, specific teams manage own insert/update, all can read projects)
CREATE POLICY "All authenticated can read projects" ON public.projects FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "Database team can manage projects" ON public.projects FOR ALL USING (public.has_role('database') OR public.has_role('super_admin'));

CREATE POLICY "All authenticated can read scrubbing" ON public.scrubbing_data FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "Scrubbing team can manage scrubbing" ON public.scrubbing_data FOR ALL USING (public.has_role('scrubbing') OR public.has_role('super_admin'));

CREATE POLICY "All authenticated can read tv" ON public.tv_data FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "TV team can manage tv" ON public.tv_data FOR ALL USING (public.has_role('tv') OR public.has_role('super_admin'));

CREATE POLICY "All authenticated can read qc" ON public.qc_data FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "QC team can manage qc" ON public.qc_data FOR ALL USING (public.has_role('qc') OR public.has_role('super_admin'));

CREATE POLICY "All authenticated can read delivery" ON public.delivery_data FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "Delivery team can manage delivery" ON public.delivery_data FOR ALL USING (public.has_role('delivery') OR public.has_role('super_admin'));


-- ============================================================
-- NOTE ON USER SEEDING:
-- Direct inserts into the `auth.users` schema are restricted in Supabase for security.
-- To create your first Super Admin:
-- 1. Go to your Supabase Project Dashboard -> Authentication -> Add User -> Create New User.
-- 2. Create a user with email "admin@stranx.com" and password "Admin123!".
-- 3. Then, run the following SQL command to assign the Super Admin role:
-- 
-- INSERT INTO public.user_roles (user_id, role)
-- SELECT id, 'super_admin' FROM auth.users WHERE email = 'admin@stranx.com';
--
-- 4. Log into the Lead Portal as "admin@stranx.com" and use the built-in Admin Console to create the rest of the users (WFM, Database, Scrub, etc.).
