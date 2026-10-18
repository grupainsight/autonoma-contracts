"""
Autonoma Platform - client identity.

Canonical client id = client_profile.client_key. Every legacy identifier (Google Ads customer id,
domain, Merchant client id, Merchant Center id) maps to it in ONE place: client_profile
(domain, ads_customer_id and the identifiers jsonb column). The SQL function resolve_client_key
(sql/004_client_identity.sql) is the production resolver; this module mirrors it for agents and
tests. Both pass conformance/identity_vectors.json.

Rules:
- Domains are compared after normalize_domain: lower case, no scheme/port/path, no leading "www.".
  Other subdomains are NOT collapsed: admin.usuwaniewszy.pl must be listed to resolve.
- An identifier may belong to one client only (ambiguity is an error, never a guess).
- Unknown identifier -> None. New flows must refuse to write without a resolved client_key.
"""

from __future__ import annotations

import re
from typing import Iterable, Optional

KINDS = ("client_key", "ads_customer_id", "domain", "merchant_client_id", "merchant_id")
# Order tried for kind="any" (legacy columns that mix id types, e.g. agent_reports.customer_id)
ANY_ORDER = ("client_key", "ads_customer_id", "merchant_client_id", "merchant_id", "domain")

_IDENTIFIER_KEYS = {
    "domain": "domains",
    "ads_customer_id": "ads_customer_ids",
    "merchant_client_id": "merchant_client_ids",
    "merchant_id": "merchant_ids",
}


class IdentityError(Exception):
    """Unknown kind or an identifier claimed by more than one client."""


def normalize_domain(value: Optional[str]) -> Optional[str]:
    if value is None:
        return None
    v = value.strip().lower()
    v = re.sub(r"^[a-z][a-z0-9+.-]*://", "", v)   # scheme
    v = re.split(r"[/?#]", v, maxsplit=1)[0]      # path, query, fragment
    v = v.split("@")[-1].split(":")[0]            # credentials, port
    v = v.rstrip(".")
    if v.startswith("www."):
        v = v[4:]
    return v or None


def _values(profile: dict, kind: str) -> list[str]:
    ids = profile.get("identifiers") or {}
    if kind == "client_key":
        out = [profile.get("client_key")]
    elif kind == "domain":
        out = [profile.get("domain")] + list(ids.get("domains") or [])
        out = [normalize_domain(d) for d in out]
    else:
        primary = [profile.get("ads_customer_id")] if kind == "ads_customer_id" else []
        out = primary + list(ids.get(_IDENTIFIER_KEYS[kind]) or [])
    return [str(v) for v in out if v not in (None, "")]


def identifier_map(profiles: Iterable[dict]) -> dict[tuple[str, str], str]:
    """(kind, value) -> client_key. Raises IdentityError when two clients claim one identifier."""
    out: dict[tuple[str, str], str] = {}
    for p in profiles:
        for kind in KINDS:
            for v in _values(p, kind):
                key = (kind, v)
                if key in out and out[key] != p["client_key"]:
                    raise IdentityError(f"{kind} {v!r} claimed by {out[key]} and {p['client_key']}")
                out[key] = p["client_key"]
    return out


def resolve_client_key(kind: str, value: Optional[str], profiles: Iterable[dict]) -> Optional[str]:
    if kind not in KINDS and kind != "any":
        raise IdentityError(f"unknown identifier kind {kind!r}")
    if value is None or str(value).strip() == "":
        return None
    m = identifier_map(profiles)
    for k in (ANY_ORDER if kind == "any" else (kind,)):
        v = normalize_domain(value) if k == "domain" else str(value).strip()
        if v and (k, v) in m:
            return m[(k, v)]
    return None
