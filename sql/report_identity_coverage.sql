-- Read-only. Knowledge Layer V1 baseline metric: rows whose client identifier does not resolve to a client_key.
-- Run after 004 (+ 004a). Target for V1: 0 unresolved in every row of this report.
SELECT 'agent_reports.customer_id' AS source, count(*) AS rows, count(*) FILTER (WHERE resolve_client_key('any', customer_id) IS NULL) AS unresolved,
       array_agg(DISTINCT customer_id) FILTER (WHERE resolve_client_key('any', customer_id) IS NULL) AS unresolved_values FROM agent_reports
UNION ALL SELECT 'agent_actions.customer_id', count(*), count(*) FILTER (WHERE resolve_client_key('any', customer_id) IS NULL),
       array_agg(DISTINCT customer_id) FILTER (WHERE resolve_client_key('any', customer_id) IS NULL) FROM agent_actions
UNION ALL SELECT 'agent_recommendations.client_id', count(*), count(*) FILTER (WHERE resolve_client_key('any', client_id) IS NULL),
       array_agg(DISTINCT client_id) FILTER (WHERE resolve_client_key('any', client_id) IS NULL) FROM agent_recommendations
UNION ALL SELECT 'agent_dashboard_modules.client_id', count(*), count(*) FILTER (WHERE resolve_client_key('any', client_id) IS NULL),
       array_agg(DISTINCT client_id) FILTER (WHERE resolve_client_key('any', client_id) IS NULL) FROM agent_dashboard_modules
UNION ALL SELECT 'stores.autonoma_client_id', count(*), count(*) FILTER (WHERE resolve_client_key('any', autonoma_client_id) IS NULL),
       array_agg(DISTINCT autonoma_client_id) FILTER (WHERE resolve_client_key('any', autonoma_client_id) IS NULL) FROM stores
UNION ALL SELECT 'stores.domain', count(*), count(*) FILTER (WHERE resolve_client_key('domain', domain) IS NULL),
       array_agg(DISTINCT domain) FILTER (WHERE resolve_client_key('domain', domain) IS NULL) FROM stores
UNION ALL SELECT 'benchmark_runs.customer_id', count(*), count(*) FILTER (WHERE resolve_client_key('any', customer_id) IS NULL),
       array_agg(DISTINCT customer_id) FILTER (WHERE resolve_client_key('any', customer_id) IS NULL) FROM benchmark_runs
UNION ALL SELECT 'knowledge_base.customer_id (non-global)', count(*), count(*) FILTER (WHERE resolve_client_key('any', customer_id) IS NULL),
       array_agg(DISTINCT customer_id) FILTER (WHERE resolve_client_key('any', customer_id) IS NULL) FROM knowledge_base WHERE customer_id IS NOT NULL
-- scans are mostly prospects, not clients: report how many client domains have history, not "unresolved"
UNION ALL SELECT 'scansite_scans with a client', count(*), count(*) FILTER (WHERE resolve_client_key('domain', domain) IS NOT NULL), NULL FROM scansite_scans
UNION ALL SELECT 'cp_scans with a client', count(*), count(*) FILTER (WHERE resolve_client_key('domain', domain) IS NOT NULL), NULL FROM cp_scans;

-- Consistency guard (would have caught the 2026-09-17 incident): a store linked to a different client
-- than the one its own domain resolves to. Expected: 0 rows.
SELECT domain, autonoma_client_id,
       resolve_client_key('any', autonoma_client_id) AS linked_client,
       resolve_client_key('domain', domain) AS domain_client
  FROM stores
 WHERE autonoma_client_id IS NOT NULL
   AND resolve_client_key('domain', domain) IS NOT NULL
   AND resolve_client_key('any', autonoma_client_id) IS DISTINCT FROM resolve_client_key('domain', domain);
