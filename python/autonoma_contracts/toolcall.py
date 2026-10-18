"""
Autonoma Platform - tool-call audit records.

One record per tool call: agent + version, client_key, tool, run id, time, a REDACTED view of the
parameters, outcome and the data sources used. Never: secrets, full personal data, conversation text,
tool result bodies. Records are written under the client of the run only (isolation), see sql/005.
"""

from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime, timezone
from typing import Any, Iterable, Optional

# Parameters safe to keep verbatim: short scalars that describe the query shape, not its content
SAFE_PARAM_KEYS = frozenset({"days", "limit", "min_impressions", "period_days", "top_n", "reps", "language"})
_SECRET_KEY = re.compile(r"(key|token|secret|password|authorization|cookie|email|phone)", re.I)


def redact_params(params: dict | None) -> dict:
    params = params or {}
    canonical = json.dumps(params, sort_keys=True, ensure_ascii=False, default=str)
    safe = {k: v for k, v in params.items()
            if k in SAFE_PARAM_KEYS and isinstance(v, (int, float, bool)) and not _SECRET_KEY.search(k)}
    return {"keys": sorted(params), "sha256": hashlib.sha256(canonical.encode()).hexdigest(), "safe": safe}


def record(*, agent: str, agent_version: str, client_key: str, run_id: str, tool: str,
           params: dict | None, ok: bool, error: Optional[BaseException | str] = None,
           sources: Iterable[str] = (), started_at: Optional[datetime] = None,
           duration_ms: Optional[int] = None) -> dict:
    if not client_key:
        raise ValueError("tool-call record needs a resolved client_key")
    err = None
    if error is not None:
        if isinstance(error, BaseException):
            err = type(error).__name__
        else:   # a short code only; anything that looks like free text is dropped
            err = str(error) if re.fullmatch(r"[A-Za-z0-9_:.\-]{1,64}", str(error)) else "ERROR"
    return {
        "agent": agent,
        "agent_version": agent_version,
        "client_key": client_key,
        "run_id": run_id,
        "tool": tool,
        "called_at": (started_at or datetime.now(timezone.utc)).isoformat(),
        "duration_ms": duration_ms,
        "params": redact_params(params),
        "status": "OK" if ok else "ERROR",
        "error_class": err,                       # class or short code only, never a message body
        "sources": sorted(set(sources)),          # e.g. ["table:cp_scans", "api:gsc"]
    }
