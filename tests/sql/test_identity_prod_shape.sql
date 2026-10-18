-- Local only. Production identifiers as read on 2026-10-18 -> 004 + 004a + coverage report.
\set ON_ERROR_STOP 1
DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role; END IF; END $$;
CREATE TABLE client_profile (client_key text PRIMARY KEY, name text, domain text, ads_customer_id text, active boolean DEFAULT true);
INSERT INTO client_profile (client_key, domain, ads_customer_id) VALUES
 ('systemyszklane','systemyszklane.eu','4660699874'), ('spcg','spcg.pl','9657129407'), ('support_online','support-online.pl','4963641094'),
 ('piccolotesoro','piccolotesoro.pl','1839755261'), ('mamyzglowy','mamyzglowy.pl','2320852709'), ('grupainsight','grupainsight.com',NULL),
 ('goodent','goodent.pl','1753777544');
CREATE TABLE agent_reports (customer_id text); INSERT INTO agent_reports VALUES ('1753777544'),('1839755261'),('2320852709'),('4660699874'),('4963641094'),('9657129407'),('grupainsight.com');
CREATE TABLE agent_actions (customer_id text); INSERT INTO agent_actions VALUES ('1753777544'),('1839755261'),('2320852709'),('4660699874'),('4963641094'),('9657129407');
CREATE TABLE agent_recommendations (client_id text); INSERT INTO agent_recommendations VALUES ('1839755261'),('4963641094'),('9657129407'),('client_piccolo_tesoro');
CREATE TABLE agent_dashboard_modules (client_id text); INSERT INTO agent_dashboard_modules VALUES ('client_piccolo_tesoro');
CREATE TABLE stores (domain text, autonoma_client_id text); INSERT INTO stores VALUES ('admin.wszystkonawszy.pl','2320852709'),('admin.usuwaniewszy.pl','client_piccolo_tesoro'),('admin.wszystkonawszy.pl',NULL),('grzebiennawszy.pl',NULL);
CREATE TABLE benchmark_runs (customer_id text); INSERT INTO benchmark_runs VALUES ('grupainsight.com');
CREATE TABLE knowledge_base (customer_id text); INSERT INTO knowledge_base VALUES ('2320852709'),('1839755261'),(NULL);
CREATE TABLE scansite_scans (domain text); INSERT INTO scansite_scans VALUES ('grupainsight.com'),('www.spcg.pl'),('spcg.pl'),('tashka.pl');
CREATE TABLE cp_scans (domain text); INSERT INTO cp_scans VALUES ('piccolotesoro.pl'),('tashka.pl');
\i sql/004_client_identity.sql
\echo --- BEFORE SEED
\i sql/report_identity_coverage.sql
\i sql/004a_client_identifiers_seed.sql
\echo --- AFTER SEED
\i sql/report_identity_coverage.sql
