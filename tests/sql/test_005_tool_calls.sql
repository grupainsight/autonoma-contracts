-- Local Postgres only.
\set ON_ERROR_STOP 1
DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role; END IF; END $$;
GRANT USAGE ON SCHEMA public TO service_role, anon, authenticated;
CREATE TABLE client_profile (client_key text PRIMARY KEY);
INSERT INTO client_profile VALUES ('spcg');
\i sql/005_agent_tool_calls.sql
INSERT INTO agent_tool_calls (agent, agent_version, client_key, run_id, tool, called_at, params, status)
VALUES ('seo', 'v2', 'spcg', 'r1', 'get_top_queries', now(), '{"keys": ["days"], "sha256": "x", "safe": {"days": 28}}', 'OK');
DO $$ BEGIN
  BEGIN INSERT INTO agent_tool_calls (agent, agent_version, client_key, run_id, tool, called_at, params, status)
        VALUES ('seo','v2','unknown','r1','t',now(),'{"keys":[],"sha256":"x"}','OK'); RAISE EXCEPTION 'TEST FAIL: unknown client accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL; END;
  BEGIN INSERT INTO agent_tool_calls (agent, agent_version, client_key, run_id, tool, called_at, params, status, error_class)
        VALUES ('seo','v2','spcg','r1','t',now(),'{"keys":[],"sha256":"x"}','ERROR','401 for jan@spcg.pl'); RAISE EXCEPTION 'TEST FAIL: free-text error accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN INSERT INTO agent_tool_calls (agent, agent_version, client_key, run_id, tool, called_at, params, status)
        VALUES ('seo','v2','spcg','r1','t',now(),'{"query":"raw text"}','OK'); RAISE EXCEPTION 'TEST FAIL: unredacted params accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  ASSERT NOT has_table_privilege('anon', 'agent_tool_calls', 'SELECT'), 'anon can read';
  ASSERT NOT has_table_privilege('authenticated', 'agent_tool_calls', 'SELECT'), 'authenticated can read';
  ASSERT has_table_privilege('service_role', 'agent_tool_calls', 'INSERT'), 'service_role cannot insert';
  ASSERT NOT has_table_privilege('service_role', 'agent_tool_calls', 'UPDATE'), 'service_role can update';
  ASSERT NOT has_table_privilege('service_role', 'agent_tool_calls', 'DELETE'), 'service_role can delete';
END $$;
\echo TOOL_CALLS_SQL_OK
