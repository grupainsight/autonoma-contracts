-- 004 Client identity. NOT APPLIED to production yet (needs approval).
-- Canonical client id = client_profile.client_key. All legacy identifiers map to it here, in one place.
-- Adds ONE column (identifiers jsonb) to the existing client_profile; no new tables.
--   identifiers = {"domains": [...], "ads_customer_ids": [...], "merchant_client_ids": [...], "merchant_ids": [...]}
-- Mirrors python/autonoma_contracts/identity.py; both pass conformance/identity_vectors.json.

ALTER TABLE client_profile ADD COLUMN IF NOT EXISTS identifiers jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE OR REPLACE FUNCTION normalize_domain(p text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT nullif(
        regexp_replace(                                             -- leading www.
          rtrim(                                                    -- trailing dot
            split_part(split_part(                                  -- port, credentials
              (regexp_split_to_array(                               -- path, query, fragment
                regexp_replace(lower(btrim(p)), '^[a-z][a-z0-9+.-]*://', ''), '[/?#]'))[1],
              ':', 1), '@', -1),
            '.'),
          '^www\.', ''),
        '')
$$;

-- One row per (kind, value) -> client_key. A view over client_profile, not a table.
CREATE OR REPLACE VIEW client_identifiers AS
    SELECT 'client_key'::text AS kind, client_key AS value, client_key FROM client_profile
    UNION ALL
    SELECT 'ads_customer_id', ads_customer_id::text, client_key FROM client_profile WHERE ads_customer_id IS NOT NULL AND ads_customer_id::text <> ''
    UNION ALL
    SELECT 'domain', normalize_domain(domain), client_key FROM client_profile WHERE normalize_domain(domain) IS NOT NULL
    UNION ALL
    SELECT 'domain', normalize_domain(d), client_key FROM client_profile, jsonb_array_elements_text(identifiers -> 'domains') d WHERE normalize_domain(d) IS NOT NULL
    UNION ALL
    SELECT 'ads_customer_id', a, client_key FROM client_profile, jsonb_array_elements_text(identifiers -> 'ads_customer_ids') a
    UNION ALL
    SELECT 'merchant_client_id', m, client_key FROM client_profile, jsonb_array_elements_text(identifiers -> 'merchant_client_ids') m
    UNION ALL
    SELECT 'merchant_id', m, client_key FROM client_profile, jsonb_array_elements_text(identifiers -> 'merchant_ids') m;

-- An identifier may belong to one client only
CREATE OR REPLACE FUNCTION client_identity_unique() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE c record;
BEGIN
    SELECT kind, value, array_agg(DISTINCT client_key) AS keys INTO c
      FROM client_identifiers GROUP BY kind, value HAVING count(DISTINCT client_key) > 1 LIMIT 1;
    IF FOUND THEN
        RAISE EXCEPTION 'IDENTITY_CONFLICT: % % claimed by %', c.kind, c.value, c.keys;
    END IF;
    RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_client_identity_unique ON client_profile;
CREATE CONSTRAINT TRIGGER trg_client_identity_unique AFTER INSERT OR UPDATE ON client_profile
    DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION client_identity_unique();

-- kind: client_key | ads_customer_id | domain | merchant_client_id | merchant_id | any
-- Returns client_key, NULL when unknown, raises on an unknown kind or a conflict.
CREATE OR REPLACE FUNCTION resolve_client_key(p_kind text, p_value text) RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE k text; v text; hit text[];
BEGIN
    IF p_kind NOT IN ('client_key', 'ads_customer_id', 'domain', 'merchant_client_id', 'merchant_id', 'any') THEN
        RAISE EXCEPTION 'IDENTITY_KIND: unknown identifier kind %', p_kind;
    END IF;
    IF p_value IS NULL OR btrim(p_value) = '' THEN RETURN NULL; END IF;
    FOREACH k IN ARRAY CASE WHEN p_kind = 'any'
        THEN ARRAY['client_key', 'ads_customer_id', 'merchant_client_id', 'merchant_id', 'domain']
        ELSE ARRAY[p_kind] END
    LOOP
        v := CASE WHEN k = 'domain' THEN normalize_domain(p_value) ELSE btrim(p_value) END;
        SELECT array_agg(DISTINCT client_key) INTO hit FROM client_identifiers WHERE kind = k AND value = v;
        IF array_length(hit, 1) > 1 THEN
            RAISE EXCEPTION 'IDENTITY_CONFLICT: % % claimed by %', k, v, hit;
        ELSIF array_length(hit, 1) = 1 THEN
            RETURN hit[1];
        END IF;
    END LOOP;
    RETURN NULL;
END $$;

REVOKE ALL ON FUNCTION resolve_client_key(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION resolve_client_key(text, text) TO service_role;
REVOKE ALL ON client_identifiers FROM PUBLIC, anon, authenticated;
GRANT SELECT ON client_identifiers TO service_role;

NOTIFY pgrst, 'reload schema';

-- ROLLBACK
-- DROP TRIGGER IF EXISTS trg_client_identity_unique ON client_profile;
-- DROP FUNCTION IF EXISTS resolve_client_key(text, text);
-- DROP FUNCTION IF EXISTS client_identity_unique();
-- DROP VIEW IF EXISTS client_identifiers;
-- DROP FUNCTION IF EXISTS normalize_domain(text);
-- ALTER TABLE client_profile DROP COLUMN IF EXISTS identifiers;
