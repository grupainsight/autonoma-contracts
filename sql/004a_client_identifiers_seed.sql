-- 004a NOT APPLIED. Data proposal for client_profile.identifiers (needs Rafał's confirmation per line).
-- Only identifiers seen in production on 2026-10-18 that do not already resolve via domain/ads_customer_id.
-- Runs after 004; the uniqueness trigger refuses any line that would give one identifier to two clients.

-- BEFORE
SELECT client_key, domain, ads_customer_id, identifiers FROM client_profile ORDER BY client_key;

BEGIN;
-- Merchant Agent writes client_piccolo_tesoro (src/clients.py) and Merchant Center 107773243
UPDATE client_profile SET identifiers = identifiers || '{"merchant_client_ids": ["client_piccolo_tesoro"], "merchant_ids": ["107773243"]}'::jsonb
 WHERE client_key = 'piccolotesoro';
-- CommercePilot stores and sales-chat sites of Mamy z głowy (headless WooCommerce backends listed explicitly;
-- subdomains are never collapsed). CONFIRM: all of these belong to the mamyzglowy client.
UPDATE client_profile SET identifiers = identifiers || '{"domains": ["usuwaniewszy.pl", "admin.usuwaniewszy.pl", "wszystkonawszy.pl", "admin.wszystkonawszy.pl", "grzebiennawszy.pl"]}'::jsonb
 WHERE client_key = 'mamyzglowy';
COMMIT;

-- AFTER: every identifier above must resolve
SELECT v, resolve_client_key('any', v) FROM unnest(ARRAY['client_piccolo_tesoro', '107773243', 'admin.usuwaniewszy.pl', 'www.wszystkonawszy.pl', 'grzebiennawszy.pl']) v;

-- ROLLBACK
-- UPDATE client_profile SET identifiers = identifiers - 'merchant_client_ids' - 'merchant_ids' WHERE client_key = 'piccolotesoro';
-- UPDATE client_profile SET identifiers = identifiers - 'domains' WHERE client_key = 'mamyzglowy';
