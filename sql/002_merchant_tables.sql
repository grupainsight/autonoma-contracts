-- Autonoma Platform - Merchant Agent Tables
-- Version: 1.0.0

-- ============================================================
-- Merchant reports - weekly JSONB snapshots
-- ============================================================
CREATE TABLE IF NOT EXISTS merchant_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id TEXT NOT NULL,
    merchant_id TEXT NOT NULL,
    report_date DATE NOT NULL,
    report_type TEXT NOT NULL CHECK (report_type IN ('weekly')) DEFAULT 'weekly',
    content JSONB NOT NULL,
    run_id UUID REFERENCES agent_runs(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_merchant_reports_client ON merchant_reports (client_id, report_date);

-- ============================================================
-- Merchant product status - snapshots with per-context status
-- ============================================================
CREATE TABLE IF NOT EXISTS merchant_product_status (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id TEXT NOT NULL,
    merchant_id TEXT NOT NULL,
    -- Full product identity (offer_id alone is not unique)
    product_id TEXT NOT NULL,
    offer_id TEXT,
    channel TEXT,
    content_language TEXT,
    feed_label TEXT,
    -- Product data
    title TEXT,
    gtin TEXT,
    product_url TEXT,
    -- Status per reporting context + country (not a single field)
    status_per_reporting_context JSONB NOT NULL DEFAULT '[]',
    -- Example:
    -- [
    --   {"reporting_context": "SHOPPING_ADS", "country_code": "PL", "status": "NOT_ELIGIBLE_OR_DISAPPROVED"},
    --   {"reporting_context": "FREE_LISTINGS", "country_code": "PL", "status": "ELIGIBLE"}
    -- ]
    issues JSONB NOT NULL DEFAULT '[]',
    price NUMERIC(12, 2),
    currency TEXT,
    availability TEXT,
    snapshot_date DATE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_merchant_product_client ON merchant_product_status (client_id, snapshot_date);
CREATE INDEX idx_merchant_product_gtin ON merchant_product_status (gtin) WHERE gtin IS NOT NULL;
CREATE INDEX idx_merchant_product_url ON merchant_product_status (product_url) WHERE product_url IS NOT NULL;
CREATE INDEX idx_merchant_product_id ON merchant_product_status (merchant_id, product_id);

-- ============================================================
-- Merchant metrics - weekly aggregates
-- ============================================================
CREATE TABLE IF NOT EXISTS merchant_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id TEXT NOT NULL,
    merchant_id TEXT NOT NULL,
    metric_date DATE NOT NULL,
    total_products INTEGER,
    approved INTEGER,
    disapproved INTEGER,
    pending INTEGER,
    impressions BIGINT,
    clicks BIGINT,
    ctr NUMERIC(6, 4),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_merchant_metrics_client ON merchant_metrics (client_id, metric_date);

-- ============================================================
-- Merchant account issues - account-level problems
-- ============================================================
CREATE TABLE IF NOT EXISTS merchant_account_issues (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id TEXT NOT NULL,
    merchant_id TEXT NOT NULL,
    issue_id TEXT,
    severity TEXT CHECK (severity IN ('critical', 'error', 'suggestion')),
    title TEXT NOT NULL,
    detail TEXT,
    snapshot_date DATE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_merchant_issues_client ON merchant_account_issues (client_id, snapshot_date);
