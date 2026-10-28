-- Local only (throwaway Postgres): psql -X -q -f tests/sql/test_merchant_performance.sql
\set ON_ERROR_STOP 1
DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role; END IF; END $$;
\i sql/001_core_tables.sql
\i sql/005_merchant_product_performance.sql
\i sql/005_merchant_product_performance.sql
\echo 005 applies twice (idempotent)

-- an unpublished load is invisible; publishing makes exactly its rows visible
INSERT INTO merchant_product_performance (client_key, merchant_id, period_start, period_end, offer_id, marketing_method,
  impressions, clicks, current_product_url, in_current_catalog, fetch_id) VALUES
 ('piccolotesoro','107773243','2026-10-19','2026-10-25','98707','ADS',10,1,'https://piccolotesoro.pl/produkt/a/',true,'00000000-0000-0000-0000-00000000000a'),
 ('piccolotesoro','107773243','2026-10-19','2026-10-25','98707','ORGANIC',20,0,'https://piccolotesoro.pl/produkt/a/',true,'00000000-0000-0000-0000-00000000000a'),
 ('piccolotesoro','107773243','2026-10-19','2026-10-25','98707','ADS',99,9,NULL,false,'00000000-0000-0000-0000-00000000000b');
DO $$ BEGIN ASSERT (SELECT count(*) FROM merchant_product_performance_published) = 0, 'nothing published yet'; END $$;
INSERT INTO merchant_performance_periods (client_key, merchant_id, period_start, period_end, fetch_id, fetched_at,
  ads_impressions, ads_clicks, organic_impressions, organic_clicks, ads_impressions_by_offer, ads_clicks_by_offer,
  organic_impressions_by_offer, organic_clicks_by_offer, offer_rows, offers, rows_without_offer, rows_unknown_method)
 VALUES ('piccolotesoro','107773243','2026-10-19','2026-10-25','00000000-0000-0000-0000-00000000000a', now(), 13,1,30,0,10,1,20,0,2,1,0,0);
DO $$ BEGIN ASSERT (SELECT count(*) FROM merchant_product_performance_published) = 2, 'only load a visible';
 ASSERT (SELECT sum(impressions) FROM merchant_product_performance_published WHERE marketing_method='ADS') = 10, 'ads rows of load a'; END $$;
-- compare-and-set publish: update only when the expected fetch_id is still current
UPDATE merchant_performance_periods SET fetch_id='00000000-0000-0000-0000-00000000000b'
 WHERE client_key='piccolotesoro' AND period_start='2026-10-19' AND fetch_id='00000000-0000-0000-0000-00000000000c';
DO $$ BEGIN ASSERT (SELECT fetch_id FROM merchant_performance_periods) = '00000000-0000-0000-0000-00000000000a', 'stale CAS must not publish'; END $$;
\echo publication and compare-and-set OK

-- constraints
DO $$ DECLARE ok boolean;
BEGIN
  BEGIN INSERT INTO merchant_performance_periods (client_key, merchant_id, period_start, period_end, fetch_id, fetched_at,
    ads_impressions, ads_clicks, organic_impressions, organic_clicks, ads_impressions_by_offer, ads_clicks_by_offer,
    organic_impressions_by_offer, organic_clicks_by_offer, offer_rows, offers, rows_without_offer, rows_unknown_method)
    VALUES ('x','1','2026-10-20','2026-10-26',gen_random_uuid(),now(),0,0,0,0,0,0,0,0,0,0,0,0); ok := false;
  EXCEPTION WHEN check_violation THEN ok := true; END; ASSERT ok, 'non-Monday week accepted';
  BEGIN INSERT INTO merchant_performance_periods (client_key, merchant_id, period_start, period_end, fetch_id, fetched_at,
    ads_impressions, ads_clicks, organic_impressions, organic_clicks, ads_impressions_by_offer, ads_clicks_by_offer,
    organic_impressions_by_offer, organic_clicks_by_offer, offer_rows, offers, rows_without_offer, rows_unknown_method)
    VALUES ('piccolotesoro','107773243','2026-10-19','2026-10-25',gen_random_uuid(),now(),0,0,0,0,0,0,0,0,0,0,0,0); ok := false;
  EXCEPTION WHEN unique_violation THEN ok := true; END; ASSERT ok, 'second publication row for a week accepted';
  BEGIN INSERT INTO merchant_product_performance (client_key, merchant_id, period_start, period_end, offer_id, marketing_method,
    impressions, clicks, in_current_catalog, fetch_id) VALUES ('x','1','2026-10-19','2026-10-25','','ADS',1,0,true,gen_random_uuid()); ok := false;
  EXCEPTION WHEN check_violation THEN ok := true; END; ASSERT ok, 'empty offer_id accepted';
  BEGIN INSERT INTO merchant_product_performance (client_key, merchant_id, period_start, period_end, offer_id, marketing_method,
    impressions, clicks, in_current_catalog, fetch_id) VALUES ('x','1','2026-10-19','2026-10-25','o','LOCAL',1,0,true,gen_random_uuid()); ok := false;
  EXCEPTION WHEN check_violation THEN ok := true; END; ASSERT ok, 'unknown marketing_method accepted';
  BEGIN INSERT INTO merchant_product_performance (client_key, merchant_id, period_start, period_end, offer_id, marketing_method,
    impressions, clicks, in_current_catalog, fetch_id) VALUES ('x','1','2026-10-19','2026-10-25','98707','ADS',1,0,true,'00000000-0000-0000-0000-00000000000a'); ok := false;
  EXCEPTION WHEN unique_violation THEN ok := true; END; ASSERT ok, 'duplicate offer in one load accepted';
END $$;
\echo constraints OK

-- access: RLS on, nothing for anon / authenticated, service_role can work
DO $$ BEGIN
  ASSERT (SELECT bool_and(relrowsecurity) FROM pg_class WHERE relname IN ('merchant_performance_periods','merchant_product_performance')), 'RLS off';
  ASSERT NOT has_table_privilege('anon','merchant_product_performance','SELECT'), 'anon can read rows';
  ASSERT NOT has_table_privilege('authenticated','merchant_performance_periods','SELECT'), 'authenticated can read periods';
  ASSERT NOT has_table_privilege('anon','merchant_product_performance_published','SELECT'), 'anon can read view';
  ASSERT has_table_privilege('service_role','merchant_product_performance','INSERT'), 'service_role cannot insert';
  ASSERT has_table_privilege('service_role','merchant_product_performance_published','SELECT'), 'service_role cannot read view';
  ASSERT (SELECT 'security_invoker=true' = ANY(reloptions) FROM pg_class WHERE relname='merchant_product_performance_published'), 'view not security_invoker';
END $$;
\echo access OK
