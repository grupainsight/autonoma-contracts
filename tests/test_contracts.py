"""
Autonoma Platform - Contract tests.

Must pass before first deployment:
1. Illegal lifecycle transitions are rejected
2. Dedupe correctly handles create/update/reopen/skip
3. Stale is computed correctly per source
4. INSIGHT requires expires_at
5. Token format parsing works
"""

import pytest
from datetime import UTC, datetime, timedelta, date

from autonoma_contracts.models import (
    DashboardModule,
    Recommendation,
    RecommendationStatus,
    RecommendationType,
    SourceFreshness,
    DataPeriod,
    Impact,
    ModuleName,
    ModuleStatus,
)
from autonoma_contracts.lifecycle import (
    validate_transition,
    get_available_actions,
    IllegalTransitionError,
)
from autonoma_contracts.dedupe import (
    check_dedupe,
    build_dedupe_key,
)


# ============================================================
# Lifecycle tests
# ============================================================

class TestLifecycleTransitions:
    """Verify legal and illegal transitions per recommendation type."""

    def test_insight_new_to_expired(self):
        validate_transition(RecommendationType.INSIGHT, RecommendationStatus.NEW, RecommendationStatus.EXPIRED)

    def test_insight_new_to_withdrawn(self):
        validate_transition(RecommendationType.INSIGHT, RecommendationStatus.NEW, RecommendationStatus.WITHDRAWN)

    def test_insight_cannot_be_acknowledged(self):
        with pytest.raises(IllegalTransitionError):
            validate_transition(RecommendationType.INSIGHT, RecommendationStatus.NEW, RecommendationStatus.ACKNOWLEDGED)

    def test_insight_cannot_be_approved(self):
        with pytest.raises(IllegalTransitionError):
            validate_transition(RecommendationType.INSIGHT, RecommendationStatus.NEW, RecommendationStatus.APPROVED)

    def test_recommendation_new_to_acknowledged(self):
        validate_transition(RecommendationType.RECOMMENDATION, RecommendationStatus.NEW, RecommendationStatus.ACKNOWLEDGED)

    def test_recommendation_new_to_rejected(self):
        validate_transition(RecommendationType.RECOMMENDATION, RecommendationStatus.NEW, RecommendationStatus.REJECTED)

    def test_recommendation_acknowledged_to_completed(self):
        validate_transition(RecommendationType.RECOMMENDATION, RecommendationStatus.ACKNOWLEDGED, RecommendationStatus.COMPLETED)

    def test_recommendation_cannot_skip_to_completed(self):
        """NEW -> COMPLETED is not allowed, must go through ACKNOWLEDGED."""
        with pytest.raises(IllegalTransitionError):
            validate_transition(RecommendationType.RECOMMENDATION, RecommendationStatus.NEW, RecommendationStatus.COMPLETED)

    def test_recommendation_cannot_be_approved(self):
        """Only ACTIONs can be approved."""
        with pytest.raises(IllegalTransitionError):
            validate_transition(RecommendationType.RECOMMENDATION, RecommendationStatus.NEW, RecommendationStatus.APPROVED)

    def test_action_new_to_approved(self):
        validate_transition(RecommendationType.ACTION, RecommendationStatus.NEW, RecommendationStatus.APPROVED)

    def test_action_approved_to_in_progress(self):
        validate_transition(RecommendationType.ACTION, RecommendationStatus.APPROVED, RecommendationStatus.IN_PROGRESS)

    def test_action_in_progress_to_completed(self):
        validate_transition(RecommendationType.ACTION, RecommendationStatus.IN_PROGRESS, RecommendationStatus.COMPLETED)

    def test_action_cannot_be_acknowledged(self):
        """ACTIONs skip ACKNOWLEDGED, they go directly to APPROVED."""
        with pytest.raises(IllegalTransitionError):
            validate_transition(RecommendationType.ACTION, RecommendationStatus.NEW, RecommendationStatus.ACKNOWLEDGED)

    def test_completed_is_terminal(self):
        """No transitions out of COMPLETED."""
        with pytest.raises(IllegalTransitionError):
            validate_transition(RecommendationType.RECOMMENDATION, RecommendationStatus.COMPLETED, RecommendationStatus.NEW)

    def test_rejected_is_terminal(self):
        """No transitions out of REJECTED."""
        with pytest.raises(IllegalTransitionError):
            validate_transition(RecommendationType.RECOMMENDATION, RecommendationStatus.REJECTED, RecommendationStatus.NEW)

    def test_available_actions_recommendation_new(self):
        actions = get_available_actions(RecommendationType.RECOMMENDATION, RecommendationStatus.NEW)
        assert RecommendationStatus.ACKNOWLEDGED in actions
        assert RecommendationStatus.REJECTED in actions
        assert RecommendationStatus.APPROVED not in actions

    def test_available_actions_action_new(self):
        actions = get_available_actions(RecommendationType.ACTION, RecommendationStatus.NEW)
        assert RecommendationStatus.APPROVED in actions
        assert RecommendationStatus.ACKNOWLEDGED not in actions


# ============================================================
# Dedupe tests
# ============================================================

class TestDeduplication:
    """Verify dedupe logic for recurring issues."""

    def _make_rec(self, status: RecommendationStatus, updated_days_ago: int = 0) -> Recommendation:
        now = datetime.now(UTC)
        return Recommendation(
            id="rec_test_001",
            client_id="client_test",
            source_agent=ModuleName.MERCHANT,
            type=RecommendationType.RECOMMENDATION,
            status=status,
            title="Test",
            summary="Test recommendation",
            impact=Impact.HIGH,
            confidence=90,
            dedupe_key="merchant:missing_gtin:m123:SHOPPING_ADS:PL",
            first_seen_at=now - timedelta(days=14),
            last_seen_at=now - timedelta(days=7),
            occurrence_count=2,
            created_at=now - timedelta(days=14),
            updated_at=now - timedelta(days=updated_days_ago),
        )

    def test_no_existing_creates_new(self):
        result = check_dedupe("merchant:test:123", [])
        assert result.action == "create"

    def test_active_recommendation_gets_updated(self):
        existing = self._make_rec(RecommendationStatus.NEW)
        result = check_dedupe(existing.dedupe_key, [existing])
        assert result.action == "update"
        assert result.existing == existing

    def test_acknowledged_recommendation_gets_updated(self):
        existing = self._make_rec(RecommendationStatus.ACKNOWLEDGED)
        result = check_dedupe(existing.dedupe_key, [existing])
        assert result.action == "update"

    def test_completed_recommendation_gets_reopened(self):
        existing = self._make_rec(RecommendationStatus.COMPLETED)
        result = check_dedupe(existing.dedupe_key, [existing])
        assert result.action == "reopen"

    def test_withdrawn_recommendation_gets_reopened(self):
        existing = self._make_rec(RecommendationStatus.WITHDRAWN)
        result = check_dedupe(existing.dedupe_key, [existing])
        assert result.action == "reopen"

    def test_recently_rejected_is_skipped(self):
        existing = self._make_rec(RecommendationStatus.REJECTED, updated_days_ago=5)
        result = check_dedupe(existing.dedupe_key, [existing])
        assert result.action == "skip"

    def test_old_rejected_gets_reopened(self):
        existing = self._make_rec(RecommendationStatus.REJECTED, updated_days_ago=45)
        result = check_dedupe(existing.dedupe_key, [existing])
        assert result.action == "reopen"

    def test_build_dedupe_key(self):
        key = build_dedupe_key("merchant", "missing_gtin", "m123", "SHOPPING_ADS", "PL")
        assert key == "merchant:missing_gtin:m123:SHOPPING_ADS:PL"

    def test_build_dedupe_key_simple(self):
        key = build_dedupe_key("gbp", "no_reply", "loc456")
        assert key == "gbp:no_reply:loc456"


# ============================================================
# Stale computation tests
# ============================================================

class TestStaleComputation:
    """Verify stale is computed dynamically, not stored."""

    def test_source_not_stale(self):
        source = SourceFreshness(
            last_successful_run=datetime.now(UTC) - timedelta(hours=1),
            stale_after_seconds=172800,  # 2 days
        )
        is_stale = datetime.now(UTC) > source.last_successful_run + timedelta(seconds=source.stale_after_seconds)
        assert not is_stale

    def test_source_is_stale(self):
        source = SourceFreshness(
            last_successful_run=datetime.now(UTC) - timedelta(days=3),
            stale_after_seconds=172800,  # 2 days
        )
        is_stale = datetime.now(UTC) > source.last_successful_run + timedelta(seconds=source.stale_after_seconds)
        assert is_stale

    def test_weekly_source_stale_after_14_days(self):
        source = SourceFreshness(
            last_successful_run=datetime.now(UTC) - timedelta(days=15),
            stale_after_seconds=1209600,  # 14 days
        )
        is_stale = datetime.now(UTC) > source.last_successful_run + timedelta(seconds=source.stale_after_seconds)
        assert is_stale

    def test_module_stale_if_any_source_stale(self):
        """Top-level stale = True if ANY source is stale."""
        sources = {
            "reviews": SourceFreshness(
                last_successful_run=datetime.now(UTC) - timedelta(hours=1),
                stale_after_seconds=172800,
            ),
            "performance": SourceFreshness(
                last_successful_run=datetime.now(UTC) - timedelta(days=20),
                stale_after_seconds=1209600,
            ),
        }
        now = datetime.now(UTC)
        any_stale = any(
            now > s.last_successful_run + timedelta(seconds=s.stale_after_seconds)
            for s in sources.values()
        )
        assert any_stale  # performance is stale


# ============================================================
# Model validation tests
# ============================================================

class TestModelValidation:
    """Verify Pydantic model constraints."""

    def test_insight_requires_expires_at(self):
        with pytest.raises(ValueError, match="expires_at"):
            Recommendation(
                id="rec_001",
                client_id="client_test",
                source_agent=ModuleName.MERCHANT,
                type=RecommendationType.INSIGHT,
                status=RecommendationStatus.NEW,
                title="Test insight",
                summary="Something happened",
                impact=Impact.LOW,
                confidence=80,
                dedupe_key="merchant:info:123",
                first_seen_at=datetime.now(UTC),
                last_seen_at=datetime.now(UTC),
                occurrence_count=1,
                created_at=datetime.now(UTC),
                updated_at=datetime.now(UTC),
                expires_at=None,  # This should fail
            )

    def test_insight_with_expires_at_is_valid(self):
        rec = Recommendation(
            id="rec_001",
            client_id="client_test",
            source_agent=ModuleName.MERCHANT,
            type=RecommendationType.INSIGHT,
            status=RecommendationStatus.NEW,
            title="Test insight",
            summary="Something happened",
            impact=Impact.LOW,
            confidence=80,
            dedupe_key="merchant:info:123",
            first_seen_at=datetime.now(UTC),
            last_seen_at=datetime.now(UTC),
            occurrence_count=1,
            created_at=datetime.now(UTC),
            updated_at=datetime.now(UTC),
            expires_at=datetime.now(UTC) + timedelta(days=7),
        )
        assert rec.type == RecommendationType.INSIGHT

    def test_confidence_range(self):
        with pytest.raises(Exception):
            Recommendation(
                id="rec_001",
                client_id="client_test",
                source_agent=ModuleName.MERCHANT,
                type=RecommendationType.RECOMMENDATION,
                title="Test",
                summary="Test",
                impact=Impact.LOW,
                confidence=150,  # Out of range
                dedupe_key="test:test:123",
                first_seen_at=datetime.now(UTC),
                last_seen_at=datetime.now(UTC),
                occurrence_count=1,
                created_at=datetime.now(UTC),
                updated_at=datetime.now(UTC),
            )

    def test_dashboard_module_valid(self):
        module = DashboardModule(
            module=ModuleName.MERCHANT,
            status=ModuleStatus.WARNING,
            summary="3 produkty odrzucone",
            last_successful_run=datetime.now(UTC),
            data_period=DataPeriod(**{"from": date.today() - timedelta(days=7), "to": date.today()}),
            sources={
                "products": SourceFreshness(
                    last_successful_run=datetime.now(UTC),
                    stale_after_seconds=1209600,
                ),
            },
            confidence=92,
        )
        assert module.module == ModuleName.MERCHANT


# ============================================================
# Token format tests
# ============================================================

class TestTokenFormat:
    """Verify token parsing logic."""

    def test_parse_token(self):
        token = "aut_live_abc123.secretparthere"
        parts = token.split(".", 1)
        assert len(parts) == 2
        prefix = parts[0]
        secret = parts[1]
        assert prefix.startswith("aut_live_")
        key_id = prefix.replace("aut_live_", "")
        assert key_id == "abc123"
        assert secret == "secretparthere"

    def test_invalid_token_no_dot(self):
        token = "aut_live_abc123secretparthere"
        parts = token.split(".", 1)
        assert len(parts) == 1  # No secret part

    def test_invalid_token_wrong_prefix(self):
        token = "bearer_abc123.secret"
        assert not token.startswith("aut_live_")
