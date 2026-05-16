-- ============================================================
-- AirLab Pro — Supabase Schema
-- Run this in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

-- ── 1. PROFILES ──────────────────────────────────────────────
-- Extends auth.users automatically via trigger
CREATE TABLE public.profiles (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name   TEXT,
  company     TEXT,
  email       TEXT,
  plan        TEXT NOT NULL DEFAULT 'free'
                CHECK (plan IN ('free','pro','enterprise')),
  reports_used INT NOT NULL DEFAULT 0,
  avatar_url  TEXT,
  pdf_signature TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email,'@',1))
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ── 2. CLIENTS ────────────────────────────────────────────────
CREATE TABLE public.clients (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  type        TEXT NOT NULL DEFAULT 'Zyrë'
                CHECK (type IN ('Zyrë','Rezidencë','Shkollë / Çerdhe','Spital / Klinikë','Hotel','Dyqan / Retail','Tjetër')),
  email       TEXT,
  phone       TEXT,
  address     TEXT,
  city        TEXT DEFAULT 'Tiranë',
  notes       TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER clients_updated_at
  BEFORE UPDATE ON public.clients
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ── 3. REPORTS ────────────────────────────────────────────────
CREATE TABLE public.reports (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id   UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  space_name  TEXT NOT NULL,
  space_type  TEXT DEFAULT 'Zyrë',
  address     TEXT,

  -- IAQ Parameters
  co2         NUMERIC(8,1),   -- ppm
  pm25        NUMERIC(6,2),   -- µg/m³
  tvoc        NUMERIC(6,3),   -- mg/m³
  humidity    NUMERIC(5,1),   -- %RH
  temperature NUMERIC(5,1),   -- °C

  -- Computed
  iaq_score   INT CHECK (iaq_score BETWEEN 0 AND 100),
  grade       TEXT CHECK (grade IN ('SHKËLQYER','MIRË','MESATAR','DOBËT')),
  ai_analysis TEXT,

  -- Meta
  measured_at TIMESTAMPTZ DEFAULT NOW(),
  notes       TEXT,
  status      TEXT NOT NULL DEFAULT 'draft'
                CHECK (status IN ('draft','done','sent')),
  pdf_url     TEXT,

  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER reports_updated_at
  BEFORE UPDATE ON public.reports
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Index for fast user queries
CREATE INDEX idx_reports_user_id ON public.reports(user_id);
CREATE INDEX idx_reports_client_id ON public.reports(client_id);
CREATE INDEX idx_clients_user_id ON public.clients(user_id);

-- ── 4. CONTACT MESSAGES ───────────────────────────────────────
CREATE TABLE public.contact_messages (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  first_name   TEXT,
  last_name    TEXT,
  email        TEXT NOT NULL,
  company      TEXT,
  subject      TEXT,
  message      TEXT NOT NULL,
  contact_pref TEXT,
  read         BOOLEAN DEFAULT FALSE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── 5. ROW LEVEL SECURITY (RLS) ──────────────────────────────
-- Enable RLS on all tables
ALTER TABLE public.profiles       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clients        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contact_messages ENABLE ROW LEVEL SECURITY;

-- PROFILES: user sees/edits only their own
CREATE POLICY "profiles_select_own" ON public.profiles
  FOR SELECT USING (auth.uid() = id);
CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE USING (auth.uid() = id);

-- CLIENTS: user sees/edits only their own
CREATE POLICY "clients_select_own" ON public.clients
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "clients_insert_own" ON public.clients
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "clients_update_own" ON public.clients
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "clients_delete_own" ON public.clients
  FOR DELETE USING (auth.uid() = user_id);

-- REPORTS: user sees/edits only their own
CREATE POLICY "reports_select_own" ON public.reports
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "reports_insert_own" ON public.reports
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "reports_update_own" ON public.reports
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "reports_delete_own" ON public.reports
  FOR DELETE USING (auth.uid() = user_id);

-- CONTACT: anyone can insert, only service_role reads
CREATE POLICY "contact_insert_anon" ON public.contact_messages
  FOR INSERT WITH CHECK (TRUE);

-- ── 6. VIEWS ─────────────────────────────────────────────────
-- Reports with client name joined
CREATE OR REPLACE VIEW public.reports_with_client AS
SELECT
  r.*,
  c.name  AS client_name,
  c.type  AS client_type,
  c.email AS client_email
FROM public.reports r
LEFT JOIN public.clients c ON c.id = r.client_id;

-- Client stats (reports count + avg score)
CREATE OR REPLACE VIEW public.client_stats AS
SELECT
  c.id,
  c.user_id,
  c.name,
  c.type,
  c.city,
  c.created_at,
  COUNT(r.id)::INT         AS reports_count,
  ROUND(AVG(r.iaq_score))::INT AS avg_score,
  MAX(r.created_at)        AS last_report_at
FROM public.clients c
LEFT JOIN public.reports r ON r.client_id = c.id
GROUP BY c.id;

-- ── 7. FUNCTIONS ──────────────────────────────────────────────
-- Increment reports_used counter on profile
CREATE OR REPLACE FUNCTION public.increment_reports_used(user_uuid UUID)
RETURNS VOID AS $$
BEGIN
  UPDATE public.profiles
  SET reports_used = reports_used + 1
  WHERE id = user_uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Reset reports_used monthly (call via pg_cron or Edge Function)
-- SELECT cron.schedule('reset-monthly', '0 0 1 * *',
--   'UPDATE public.profiles SET reports_used = 0');

-- ── 8. SEED DATA (optional — remove in production) ───────────
-- INSERT INTO public.clients (user_id, name, type, city)
-- VALUES ('YOUR-USER-UUID', 'Klient Test', 'Zyrë', 'Tiranë');
