# autonoma-contracts

Shared contracts, schemas and migrations for the Autonoma platform.

All agents (Ads, SEO, GBP, Merchant) and the Autonoma API import from this repo to ensure consistent data structures.

## Structure

```
schemas/          JSON Schema definitions
openapi/          Autonoma API v1 OpenAPI spec
sql/              Supabase migration files (run in order)
python/           Python package with Pydantic models + lifecycle validation
tests/            Contract tests (lifecycle transitions, dedupe, stale, token isolation)
```

## Versioning

This repo follows semver. Current: **1.0.0**

Breaking changes to schemas or API contract require a major version bump.

## Usage in agents

```bash
pip install -e git+https://github.com/grupainsight/autonoma-contracts.git#egg=autonoma-contracts&subdirectory=python
```

Or copy `python/autonoma_contracts/` into agent repo as a submodule.
