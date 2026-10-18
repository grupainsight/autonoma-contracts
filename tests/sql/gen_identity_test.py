"""Builds a psql test from conformance/identity_vectors.json, so SQL and Python check the same cases.
Run against a throwaway Postgres only:  python3 tests/sql/gen_identity_test.py | psql -X -q"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
V = json.load(open(os.path.join(ROOT, "conformance", "identity_vectors.json")))


def lit(v):
    return "NULL" if v is None else "'" + str(v).replace("'", "''") + "'"


def profiles_sql(profiles):
    rows = []
    for p in profiles:
        rows.append(f"INSERT INTO client_profile (client_key, domain, ads_customer_id, identifiers) VALUES "
                    f"({lit(p['client_key'])}, {lit(p.get('domain'))}, {lit(p.get('ads_customer_id'))}, {lit(json.dumps(p.get('identifiers') or {}))}::jsonb);")
    return "\n".join(rows)


out = [r"\set ON_ERROR_STOP 1", "DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;",
       "DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon; END IF;"
       " IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated; END IF;"
       " IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role; END IF; END $$;",
       # production shape of client_profile (subset of columns, read 2026-10-18)
       "CREATE TABLE client_profile (client_key text PRIMARY KEY, name text, domain text, ads_customer_id text, active boolean DEFAULT true);",
       rf"\i {ROOT}/sql/004_client_identity.sql"]
for raw, exp in V["normalize_domain"]:
    out.append(f"DO $$ BEGIN ASSERT normalize_domain({lit(raw)}) IS NOT DISTINCT FROM {lit(exp)}, {lit('normalize ' + str(raw) + ': ')} || coalesce(normalize_domain({lit(raw)}), 'NULL'); END $$;")
out.append(profiles_sql(V["profiles"]))
for kind, value, exp in V["resolve"]:
    if exp == "ERROR":
        out.append(f"DO $$ BEGIN PERFORM resolve_client_key({lit(kind)}, {lit(value)}); RAISE EXCEPTION 'TEST FAIL no error {kind}'; "
                   f"EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE 'IDENTITY_KIND%' THEN RAISE; END IF; END $$;")
    else:
        out.append(f"DO $$ BEGIN ASSERT resolve_client_key({lit(kind)}, {lit(value)}) IS NOT DISTINCT FROM {lit(exp)}, "
                   f"{lit('resolve ' + kind + ' ' + str(value) + ': ')} || coalesce(resolve_client_key({lit(kind)}, {lit(value)}), 'NULL'); END $$;")
for i, case in enumerate(V["conflicts"]):
    out.append("TRUNCATE client_profile;")
    first, second = case["profiles"][0], case["profiles"][1:]
    out.append(profiles_sql([first]))
    out.append(f"DO $$ BEGIN {profiles_sql(second)} RAISE EXCEPTION 'TEST FAIL conflict {i} accepted'; "
               f"EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE 'IDENTITY_CONFLICT%' THEN RAISE; END IF; END $$;")
out.append("DO $$ BEGIN ASSERT NOT has_function_privilege('anon', 'resolve_client_key(text,text)', 'EXECUTE'), 'anon can resolve';"
           " ASSERT NOT has_table_privilege('authenticated', 'client_identifiers', 'SELECT'), 'authenticated can read map'; END $$;")
out.append(r"\echo IDENTITY_SQL_CONFORMANCE_OK")
print("\n".join(out))
