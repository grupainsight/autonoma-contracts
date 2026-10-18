"""
Autonoma Platform - policy for operations that change data (shared rules, not shared middleware).

Every mutating operation, in Python or TypeScript, carries a MutationRequest and is checked with the
same rules (conformance/mutation_vectors.json). Implementations stay native to their runtime; e.g.
CommercePilot's cp_change_recommendation_status (SQL) and the Ads Agent action lifecycle.

Rules
1. client_key is resolved (autonoma_contracts.identity) before anything else.
2. The actor is allowed for this operation (policy.allowed_actors) and acts for this client.
3. resource_id names one resource that belongs to client_key (checked by the implementation's read).
4. The requested scope is within the approved scope (an approval covers what it names, nothing more).
5. expected_state must equal the current state (optimistic check; a mismatch = conflict, no write).
6. idempotency_key is required; replaying the same key returns the first result, never a second write.
7. Every accepted mutation produces an event; every attempt produces a result (OK / REFUSED / CONFLICT / FAILED).
8. compensation is recorded when the operation can be undone (rollback payload), else marked irreversible,
   and irreversible operations always require approval.
"""

from __future__ import annotations

import re
from enum import Enum
from typing import Any, Optional

from pydantic import BaseModel, Field


class Outcome(str, Enum):
    OK = "OK"
    REFUSED = "REFUSED"
    CONFLICT = "CONFLICT"
    FAILED = "FAILED"
    REPLAYED = "REPLAYED"


class MutationRequest(BaseModel):
    client_key: str
    actor_type: str                    # AGENT | CLIENT_USER | GI_USER | SYSTEM
    actor_id: str
    operation: str                     # e.g. recommendation.status, ads.add_negative_keyword, catalog.publish
    resource_id: str
    expected_state: Optional[Any] = None
    requested: dict = Field(default_factory=dict)       # what will change
    approved_scope: Optional[dict] = None               # what the approval covers (same keys as requested)
    idempotency_key: str
    compensation: Optional[dict] = None                 # rollback payload, None = irreversible


class Policy(BaseModel):
    operation: str
    allowed_actors: list[str]
    requires_approval: bool = False


IDEMPOTENCY_RE = re.compile(r"^[A-Za-z0-9:_\-.]{8,128}$")


def check(req: MutationRequest, policy: Policy, current_state: Any, resource_client_key: Optional[str],
          seen_keys: Optional[set] = None) -> tuple[Outcome, str]:
    """Pure decision. The caller performs the write only on OK, and records the event + result either way."""
    if req.operation != policy.operation:
        return Outcome.REFUSED, "OPERATION_MISMATCH"
    if not req.client_key:
        return Outcome.REFUSED, "CLIENT_UNRESOLVED"
    if not IDEMPOTENCY_RE.match(req.idempotency_key or ""):
        return Outcome.REFUSED, "IDEMPOTENCY_KEY_INVALID"
    if seen_keys is not None and req.idempotency_key in seen_keys:
        return Outcome.REPLAYED, "IDEMPOTENCY_KEY_SEEN"
    if req.actor_type not in policy.allowed_actors:
        return Outcome.REFUSED, "ACTOR_NOT_ALLOWED"
    if resource_client_key != req.client_key:
        return Outcome.REFUSED, "RESOURCE_OF_OTHER_CLIENT"          # also: resource not found
    needs_approval = policy.requires_approval or req.compensation is None
    if needs_approval:
        if not req.approved_scope:
            return Outcome.REFUSED, "APPROVAL_REQUIRED"
        for k, v in req.requested.items():
            if req.approved_scope.get(k) != v:
                return Outcome.REFUSED, "OUTSIDE_APPROVED_SCOPE"
    if req.expected_state != current_state:
        return Outcome.CONFLICT, "STATE_CHANGED"
    return Outcome.OK, "OK"
