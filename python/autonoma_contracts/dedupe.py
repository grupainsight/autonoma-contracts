from datetime import UTC
"""
Autonoma Platform - Recommendation deduplication.

Prevents agents from creating duplicate recommendations
for the same ongoing issue across weekly snapshots.

Rules:
- Same problem still exists -> update last_seen_at + occurrence_count
- Problem disappeared -> COMPLETED or WITHDRAWN
- Problem returned after resolution -> new recommendation with supersedes link
"""

from datetime import datetime
from typing import Optional

from autonoma_contracts.models import (
    Recommendation,
    RecommendationStatus,
)


class DedupeResult:
    """Result of deduplication check."""

    def __init__(
        self,
        action: str,
        existing: Optional[Recommendation] = None,
    ):
        self.action = action  # "create", "update", "reopen", "skip"
        self.existing = existing

    def __repr__(self) -> str:
        return f"DedupeResult(action={self.action})"


def check_dedupe(
    dedupe_key: str,
    existing_recommendations: list[Recommendation],
    now: Optional[datetime] = None,
) -> DedupeResult:
    """
    Check whether a new recommendation should be created or an existing one updated.

    Args:
        dedupe_key: The deterministic key for this issue
        existing_recommendations: All recommendations for the same client with this dedupe_key,
                                  ordered by created_at DESC
        now: Current timestamp (for testing)

    Returns:
        DedupeResult with action:
        - "create": No existing record, create new
        - "update": Active record exists, update last_seen_at and occurrence_count
        - "reopen": Previously resolved, create new with supersedes link
        - "skip": Existing record in terminal state that shouldn't be reopened
    """
    if now is None:
        now = datetime.now(UTC)

    if not existing_recommendations:
        return DedupeResult(action="create")

    latest = existing_recommendations[0]

    # Active statuses: issue is still being tracked
    active_statuses = {
        RecommendationStatus.NEW,
        RecommendationStatus.ACKNOWLEDGED,
        RecommendationStatus.APPROVED,
        RecommendationStatus.IN_PROGRESS,
    }

    # Resolved statuses: issue was handled, can be reopened
    resolved_statuses = {
        RecommendationStatus.COMPLETED,
        RecommendationStatus.WITHDRAWN,
        RecommendationStatus.EXPIRED,
    }

    if latest.status in active_statuses:
        return DedupeResult(action="update", existing=latest)

    if latest.status in resolved_statuses:
        return DedupeResult(action="reopen", existing=latest)

    if latest.status == RecommendationStatus.REJECTED:
        # User explicitly rejected this - don't nag them
        # But if it's been more than 30 days, allow reopening
        if latest.updated_at and (now - latest.updated_at).days > 30:
            return DedupeResult(action="reopen", existing=latest)
        return DedupeResult(action="skip", existing=latest)

    return DedupeResult(action="create")


def build_dedupe_key(
    agent: str,
    issue_type: str,
    context_id: str,
    *scope_parts: str,
) -> str:
    """
    Build a deterministic dedupe key.

    Examples:
        build_dedupe_key("merchant", "missing_gtin", "merchant_123", "SHOPPING_ADS", "PL")
        -> "merchant:missing_gtin:merchant_123:SHOPPING_ADS:PL"

        build_dedupe_key("gbp", "no_reply_review", "location_456")
        -> "gbp:no_reply_review:location_456"
    """
    parts = [agent, issue_type, context_id] + list(scope_parts)
    return ":".join(parts)
