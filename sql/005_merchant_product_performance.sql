-- Autonoma Platform - Merchant product performance (paid / free per offer, weekly)
-- Version: 1.1.0 (additive: two tables and one view, no change to existing objects)
--
-- Source: Merchant Reports API v1, product_performance_view, one ISO week (Monday-Sunday) per load.
--
-- Reading rules (also in docs/merchant-product-performance.md):
-- * A week is published only by its row in merchant_performance_periods. Rows of
--   merchant_product_performance count only when their fetch_id equals the
--   period's fetch_id; read them through merchant_product_performance_published.
-- * A missing offer row does NOT mean zero: the API leaves out part of the
--   traffic when it splits by offer. Channel totals and completeness are in
--   merchant_performance_periods; per-offer values are a lower bound.
-- * ADS and ORGANIC are separate channels. Do not add them up.
-- * current_product_url / in_current_catalog describe the catalog snapshot of
--   the load (catalog_snapshot_date), not the product's URL during the week.

CREATE TABLE IF NOT EXISTS merchant_performance_periods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_key TEXT NOT NULL,                  -- client_profile.client_key (resolve_client_key)
    merchant_id TEXT NOT NULL,
    period_start DATE NOT NULL,                -- Monday
    period_end DATE NOT NULL,                  -- Sunday
    fetch_id UUID NOT NULL,                    -- the published load
    fetched_at TIMESTAMPTZ NOT NULL,
    run_id UUID REFERENCES agent_runs(id),
    catalog_snapshot_date DATE,                -- snapshot used for current_product_url / in_current_catalog
    -- channel totals: query without offer_id
    ads_impressions BIGINT NOT NULL,
    ads_clicks BIGINT NOT NULL,
    organic_impressions BIGINT NOT NULL,
    organic_clicks BIGINT NOT NULL,
    -- sums of the per-offer rows of this load (completeness = by_offer / total)
    ads_impressions_by_offer BIGINT NOT NULL,
    ads_clicks_by_offer BIGINT NOT NULL,
    organic_impressions_by_offer BIGINT NOT NULL,
    organic_clicks_by_offer BIGINT NOT NULL,
    offer_rows INTEGER NOT NULL,
    offers INTEGER NOT NULL,
    rows_without_offer INTEGER NOT NULL,       -- rows with an empty offer_id (in totals, not in offer rows)
    rows_unknown_method INTEGER NOT NULL,      -- rows with a marketing_method other than ADS / ORGANIC
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (client_key, merchant_id, period_start),
    CHECK (period_end = period_start + 6),
    CHECK (EXTRACT(ISODOW FROM period_start) = 1)
);

CREATE TABLE IF NOT EXISTS merchant_product_performance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_key TEXT NOT NULL,
    merchant_id TEXT NOT NULL,
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    offer_id TEXT NOT NULL CHECK (offer_id <> ''),
    marketing_method TEXT NOT NULL CHECK (marketing_method IN ('ADS', 'ORGANIC')),
    impressions BIGINT NOT NULL CHECK (impressions >= 0),   -- lower bound, see periods
    clicks BIGINT NOT NULL CHECK (clicks >= 0),
    current_product_url TEXT,                  -- feed link in the load's catalog snapshot, NOT historical
    in_current_catalog BOOLEAN NOT NULL,       -- offer present in that snapshot, NOT historical
    fetch_id UUID NOT NULL,                    -- load that wrote the row; visible only when published
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (fetch_id, offer_id, marketing_method),
    CHECK (period_end = period_start + 6)
);

CREATE INDEX IF NOT EXISTS idx_mpp_load ON merchant_product_performance (client_key, merchant_id, period_start, fetch_id);
CREATE INDEX IF NOT EXISTS idx_mpp_offer ON merchant_product_performance (client_key, offer_id);
CREATE INDEX IF NOT EXISTS idx_mpp_url ON merchant_product_performance (client_key, current_product_url)
    WHERE current_product_url IS NOT NULL;

-- Only rows of published loads.
CREATE OR REPLACE VIEW merchant_product_performance_published
WITH (security_invoker = true) AS
SELECT r.client_key, r.merchant_id, r.period_start, r.period_end, r.offer_id, r.marketing_method,
       r.impressions, r.clicks, r.current_product_url, r.in_current_catalog,
       p.catalog_snapshot_date, r.fetch_id
FROM merchant_product_performance r
JOIN merchant_performance_periods p
  ON p.client_key = r.client_key AND p.merchant_id = r.merchant_id
 AND p.period_start = r.period_start AND p.fetch_id = r.fetch_id;

-- Access: agents use the service role. Nothing is exposed to anon / authenticated.
ALTER TABLE merchant_performance_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE merchant_product_performance ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON merchant_performance_periods, merchant_product_performance, merchant_product_performance_published
    FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON merchant_performance_periods, merchant_product_performance TO service_role;
GRANT SELECT ON merchant_product_performance_published TO service_role;
