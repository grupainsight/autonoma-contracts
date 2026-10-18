# Mutating operations and tool-call audit (P1)

Shared **rules, contracts and conformance tests**, not one middleware. Python agents use
`autonoma_contracts.mutation` / `.toolcall`; TypeScript and SQL implementations pass the same vectors
(`conformance/mutation_vectors.json`).

## Every mutating operation carries

| Element | Field | Checked by |
| --- | --- | --- |
| Client identity | `client_key` (resolved, 004) | caller, before anything else |
| Allowed actor | `actor_type`, `actor_id` vs `Policy.allowed_actors` | `check()` |
| Resource | `resource_id` + its owner = `client_key` | caller's read, `check()` |
| Approved scope | `approved_scope` covers every key of `requested` | `check()` (always for irreversible ops) |
| Current state | `expected_state` = state read now, else CONFLICT | `check()` + conditional write |
| Idempotency | `idempotency_key`, replay returns the first result | `check()` + unique key at the write |
| Event history | one event per accepted change | implementation (same transaction) |
| Result | OK / REFUSED / CONFLICT / FAILED / REPLAYED | implementation |
| Compensation | `compensation` payload, or irreversible = approval required | `check()` |

## Where we stand (2026-10-18)

| Operation | Implementation | Gaps |
| --- | --- | --- |
| Recommendation status from CommercePilot | `cp_change_recommendation_status` (one transaction, client + state + lifecycle + event) | no idempotency key (state check makes a replay a CONFLICT, not a second write) |
| SEO Agent shared-memory reads | bound to the account (seo-agent `fix(tools)`) | read-only, no mutation |
| Ads Agent actions | propose/approve/execute + `agent_actions`, executor guard | to map field by field against this contract (next PR) |
| CommercePilot publish | `publish_jobs`, per-field conflict hashes, rollback_data | idempotency key per job to confirm |

## Tool-call audit

`autonoma_contracts.toolcall.record()` builds the row for `agent_tool_calls` (sql/005, needs approval):
agent + version, `client_key`, run id, tool, time, duration, params as `{keys, sha256, safe}` (only short
numeric shape parameters kept verbatim), status, error class (never message text), sources. The table
is append-only for agents, unreadable for anon/authenticated, keyed by client, purged after 180 days.
Wiring into the Ads and SEO agent loops follows once 004 + 005 are approved.
