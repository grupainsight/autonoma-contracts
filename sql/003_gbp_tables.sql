-- Autonoma Platform - GBP Agent Tables
-- Version: 1.0.0
--
-- IMPORTANT: Google Business Profile API data retention policy
-- All data from GBP APIs (raw AND aggregated) has a maximum TTL of 30 days.
-- This includes review text, ratings, performance metrics, and any values
-- derived from them. Only internal operational data (recommendation IDs,
-- lifecycle events, timestamps) may be stored indefinitely.

-- ============================================================
-- GBP reports - weekly JSONB snapshots (TTL 30 days)
-- ============================================================
CREATE TABLE IF NOT EXISTS gbp_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id TEXT NOT NULL,
    account_id TEXT NOT NULL,
    location_id TEXT NOT NULL,
    report_date DATE NOT NULL,
    report_type TEXT NOT NULL CHECK (report_type IN ('weekly', 'daily_review')),
    content JSONB NOT NULL,
    run_id UUID REFERENCES agent_runs(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- TTL: delete after 30 days
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '30 days')
);

CREATE INDEX idx_gbp_reports_client ON gbp_reports (client_id, report_date);
CREATE INDEX idx_gbp_reports_expires ON gbp_reports (expires_at);

-- ============================================================
-- GBP metrics - performance data (TTL 30 days)
-- All values originate from GBP Performance API
-- ============================================================
CREATE TABLE IF NOT EXISTS gbp_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id TEXT NOT NULL,
    location_id TEXT NOT NULL,
    metric_date DATE NOT NULL,
    impressions_desktop_maps INTEGER,
    impressions_desktop_search INTEGER,
    impressions_mobile_maps INTEGER,
    impressions_mobile_search INTEGER,
    direction_requests INTEGER,
    call_clicks INTEGER,
    website_clicks INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- TTL: delete after 30 days
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '30 days')
);

CREATE INDEX idx_gbp_metrics_client ON gbp_metrics (client_id, metric_date);
CREATE INDEX idx_gbp_metrics_expires ON gbp_metrics (expires_at);

-- ============================================================
-- GBP reviews raw - full review data (TTL 30 days)
-- Contains text, rating, reviewer name - all GBP API data
-- ============================================================
CREATE TABLE IF NOT EXISTS gbp_reviews_raw (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id TEXT NOT NULL,
    location_id TEXT NOT NULL,
    review_id TEXT NOT NULL,
    rating INTEGER CHECK (rating BETWEEN 1 AND 5),
    text TEXT,
    reply_text TEXT,
    reply_status TEXT,
    reviewer_display_name TEXT,
    create_time TIMESTAMPTZ,
    detected_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- TTL: delete after 30 days (Google policy)
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '30 days')
);

CREATE INDEX idx_gbp_reviews_raw_client ON gbp_reviews_raw (client_id, detected_at);
CREATE INDEX idx_gbp_reviews_raw_expires ON gbp_reviews_raw (expires_at);

-- ============================================================
-- GBP review events - internal operational data (NO TTL)
-- Contains only our own data: event IDs, actions taken, timestamps
-- No GBP API data: no review_id, no rating, no text, no reviewer
-- ============================================================
CREATE TABLE IF NOT EXISTS gbp_review_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id TEXT NOT NULL,
    location_id TEXT NOT NULL,
    internal_event_id TEXT NOT NULL,
    recommendation_id TEXT REFERENCES agent_recommendations(id),
    action_taken TEXT,
    detected_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_gbp_review_events_client ON gbp_review_events (client_id, detected_at);

-- ============================================================
-- Cleanup function - call via cron or Supabase Edge Function
-- Deletes all GBP API data older than 30 days
-- ============================================================
CREATE OR REPLACE FUNCTION cleanup_gbp_expired_data()
RETURNS void AS $$
BEGIN
    DELETE FROM gbp_reviews_raw WHERE expires_at < now();
    DELETE FROM gbp_metrics WHERE expires_at < now();
    DELETE FROM gbp_reports WHERE expires_at < now();
END;
$$ LANGUAGE plpgsql;
