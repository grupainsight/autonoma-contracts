-- Autonoma Platform - Core Tables
-- Run against shared Supabase instance
-- Version: 1.0.0

-- ============================================================
-- Dashboard modules - one row per agent per client, upserted
-- ============================================================
CREATE TABLE IF NOT EXISTS agent_dashboard_modules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id TEXT NOT NULL,
    module TEXT NOT NULL CHECK (module IN ('ads', 'seo', 'gbp', 'merchant')),
    status TEXT NOT NULL CHECK (status IN ('ok', 'warning', 'critical', 'error', 'no_data')),
    summary TEXT NOT NULL,
    data_period_from DATE,
    data_period_to DATE,
    last_successful_run TIMESTAMPTZ NOT NULL,
    sources JSONB NOT NULL DEFAULT '{}',
    confidence INTEGER NOT NULL CHECK (confidence BETWEEN 0 AND 100),
    metrics JSONB NOT NULL DEFAULT '{}',
    top_issue JSONB,
    run_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (client_id, module)
);

CREATE INDEX idx_dashboard_modules_client ON agent_dashboard_modules (client_id);

-- ============================================================
-- Recommendations - unified across all agents
-- ============================================================
CREATE TABLE IF NOT EXISTS agent_recommendations (
    id TEXT PRIMARY KEY,
    client_id TEXT NOT NULL,
    source_agent TEXT NOT NULL CHECK (source_agent IN ('ads', 'seo', 'gbp', 'merchant')),
    type TEXT NOT NULL CHECK (type IN ('INSIGHT', 'RECOMMENDATION', 'ACTION')),
    status TEXT NOT NULL CHECK (status IN ('NEW', 'ACKNOWLEDGED', 'APPROVED', 'REJECTED', 'IN_PROGRESS', 'COMPLETED', 'WITHDRAWN', 'EXPIRED')),
    title TEXT NOT NULL,
    summary TEXT NOT NULL,
    recommended_action TEXT,
    impact TEXT NOT NULL CHECK (impact IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    confidence INTEGER NOT NULL CHECK (confidence BETWEEN 0 AND 100),
    reason_codes JSONB NOT NULL DEFAULT '[]',
    evidence JSONB NOT NULL DEFAULT '[]',
    requires_approval BOOLEAN NOT NULL DEFAULT false,
    -- Deduplication
    dedupe_key TEXT NOT NULL,
    subject_key TEXT,
    first_seen_at TIMESTAMPTZ NOT NULL,
    last_seen_at TIMESTAMPTZ NOT NULL,
    occurrence_count INTEGER NOT NULL DEFAULT 1,
    resolved_at TIMESTAMPTZ,
    supersedes_recommendation_id TEXT REFERENCES agent_recommendations(id),
    -- Lifecycle
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_recommendations_client ON agent_recommendations (client_id);
CREATE INDEX idx_recommendations_client_status ON agent_recommendations (client_id, status);
CREATE INDEX idx_recommendations_dedupe ON agent_recommendations (client_id, dedupe_key);
CREATE INDEX idx_recommendations_source ON agent_recommendations (source_agent);

-- Constraint: INSIGHTs must have expires_at
-- Enforced in application layer, not DB, because agent sets it on creation

-- ============================================================
-- Recommendation events - audit trail for status changes
-- ============================================================
CREATE TABLE IF NOT EXISTS agent_recommendation_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recommendation_id TEXT NOT NULL REFERENCES agent_recommendations(id) ON DELETE CASCADE,
    previous_status TEXT NOT NULL,
    new_status TEXT NOT NULL,
    actor_type TEXT NOT NULL CHECK (actor_type IN ('AGENT', 'CLIENT_USER', 'GI_USER', 'SYSTEM')),
    actor_id TEXT,
    source TEXT NOT NULL CHECK (source IN ('agent', 'plugin', 'email', 'api', 'system')),
    comment TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_rec_events_recommendation ON agent_recommendation_events (recommendation_id);
CREATE INDEX idx_rec_events_created ON agent_recommendation_events (created_at);

-- ============================================================
-- Agent runs - execution tracking and cost accounting
-- ============================================================
CREATE TABLE IF NOT EXISTS agent_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id TEXT NOT NULL,
    agent TEXT NOT NULL CHECK (agent IN ('ads', 'seo', 'gbp', 'merchant')),
    job_type TEXT NOT NULL CHECK (job_type IN ('weekly', 'daily', 'on_demand')),
    scheduled_for TIMESTAMPTZ,
    started_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    status TEXT NOT NULL CHECK (status IN ('RUNNING', 'SUCCESS', 'PARTIAL', 'FAILED', 'SKIPPED')),
    error_code TEXT,
    error_message TEXT,
    input_records INTEGER,
    output_records INTEGER,
    llm_used BOOLEAN NOT NULL DEFAULT false,
    input_tokens INTEGER,
    output_tokens INTEGER,
    llm_cost_usd NUMERIC(10, 6),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_agent_runs_client ON agent_runs (client_id, agent);
CREATE INDEX idx_agent_runs_status ON agent_runs (status);
CREATE INDEX idx_agent_runs_started ON agent_runs (started_at);

-- ============================================================
-- API installations - token auth for consumers (WP plugin etc)
-- ============================================================
CREATE TABLE IF NOT EXISTS api_installations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key_id TEXT NOT NULL UNIQUE,
    client_id TEXT NOT NULL,
    site_url TEXT NOT NULL,
    secret_hash TEXT NOT NULL,
    enabled_modules JSONB NOT NULL DEFAULT '["ads", "seo", "gbp", "merchant"]',
    status TEXT NOT NULL CHECK (status IN ('active', 'suspended', 'revoked')) DEFAULT 'active',
    token_expires_at TIMESTAMPTZ,
    last_rotated_at TIMESTAMPTZ,
    last_seen_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_installations_key ON api_installations (key_id);
CREATE INDEX idx_installations_client ON api_installations (client_id);
