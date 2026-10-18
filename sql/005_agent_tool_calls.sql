-- 005 Tool-call audit. NOT APPLIED (needs approval).
-- Why a new table: agent_runs has one row per run (no per-call detail), agent_reports is per report and
-- is not written when a run fails, and the 2026-10-18 RAG incident could not be ruled in or out because
-- no tool call was recorded. One row per call, keyed by client_key, redacted (autonoma_contracts.toolcall).
-- Depends on 004 (client_profile.client_key as the canonical id).

CREATE TABLE IF NOT EXISTS agent_tool_calls (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    agent text NOT NULL CHECK (agent IN ('ads', 'seo', 'gbp', 'merchant', 'sales', 'commercepilot')),
    agent_version text NOT NULL,
    client_key text NOT NULL REFERENCES client_profile(client_key),
    run_id text NOT NULL,
    tool text NOT NULL,
    called_at timestamptz NOT NULL,
    duration_ms integer,
    params jsonb NOT NULL,                  -- {keys, sha256, safe}: never raw values beyond the safe list
    status text NOT NULL CHECK (status IN ('OK', 'ERROR')),
    error_class text CHECK (error_class IS NULL OR error_class ~ '^[A-Za-z0-9_:.\-]{1,64}$'),
    sources jsonb NOT NULL DEFAULT '[]',
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (jsonb_typeof(params) = 'object' AND params ? 'sha256' AND params ? 'keys')
);
CREATE INDEX IF NOT EXISTS idx_tool_calls_client_time ON agent_tool_calls (client_key, called_at DESC);
CREATE INDEX IF NOT EXISTS idx_tool_calls_run ON agent_tool_calls (run_id);

-- Service role only (agents); clients never read it directly
ALTER TABLE agent_tool_calls ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON agent_tool_calls FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON agent_tool_calls TO service_role;     -- append-only: no UPDATE/DELETE grant

-- Retention: 180 days (enough for experiment windows), run by pg_cron if enabled
CREATE OR REPLACE FUNCTION purge_old_tool_calls() RETURNS void LANGUAGE sql AS $$
    DELETE FROM agent_tool_calls WHERE called_at < now() - interval '180 days';
$$;
REVOKE ALL ON FUNCTION purge_old_tool_calls() FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- ROLLBACK
-- DROP FUNCTION IF EXISTS purge_old_tool_calls(); DROP TABLE IF EXISTS agent_tool_calls;
