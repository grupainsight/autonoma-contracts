# Client identity (Knowledge Layer V1)

**Canonical id: `client_profile.client_key`.** Every new flow (observations, recommendations, tool-call logs,
experiments) writes `client_key`. Legacy identifiers are mapped in one place: `client_profile`
(`domain`, `ads_customer_id`, `identifiers` jsonb) via `resolve_client_key(kind, value)` in the database
(`sql/004_client_identity.sql`) and `autonoma_contracts.identity` in Python. Both pass
`conformance/identity_vectors.json`; a TypeScript copy must pass the same file.

| Legacy identifier | Where it lives today | Kind |
| --- | --- | --- |
| Google Ads customer id | `agent_reports`, `agent_actions`, `agent_recommendations` (Ads), `knowledge_base` | `ads_customer_id` |
| Domain | `agent_reports` (grupainsight.com), `benchmark_*`, `scansite_scans`, `cp_scans`, `stores` | `domain` |
| Merchant client id | `agent_recommendations`, `agent_dashboard_modules`, `agent_runs`, `merchant_*` | `merchant_client_id` |
| Merchant Center id | Merchant Agent config | `merchant_id` |
| CommercePilot store | `stores.autonoma_client_id` (set by GI staff only, must resolve) | via the stored id |

## Rules

- One identifier belongs to one client. The trigger on `client_profile` refuses a conflict; the resolver raises instead of guessing.
- One client may have many domains, Ads accounts and Merchant ids (`identifiers` arrays).
- Domains are compared after `normalize_domain`: lower case, no scheme, port, path or leading `www.`.
  Other subdomains are never collapsed: `admin.usuwaniewszy.pl` resolves only because it is listed.
- An unresolved identifier is a finding, not a default: new flows refuse to write without a `client_key`.
- `sql/report_identity_coverage.sql` is the V1 metric (target: 0 unresolved) and includes the guard that
  flags a store linked to a different client than its own domain (the 2026-09-17 incident).

## Decision: Merchant Agent key

Merchant keeps writing `client_piccolo_tesoro` for now; it is mapped through
`identifiers.merchant_client_ids`. Switching its config to `client_key` (`piccolotesoro`) happens only
together with a one-off rename of its history (`merchant_*` with ~120k rows, 10 recommendations,
1 dashboard module, runs), otherwise `get_previous_snapshot` loses week-over-week continuity.
That rename is a separate, approved migration. Until then cross-agent reads go through the resolver:
today Merchant's `get_ads_data('client_piccolo_tesoro')` finds nothing, because Ads data is keyed by
`1839755261`.
