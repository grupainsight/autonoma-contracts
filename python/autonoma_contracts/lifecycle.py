"""
Autonoma Platform - Recommendation lifecycle state machine.

Defines legal status transitions per recommendation type.
All agents and the API must validate transitions through this module.
Illegal transitions raise IllegalTransitionError.
"""

from autonoma_contracts.models import RecommendationType, RecommendationStatus


class IllegalTransitionError(Exception):
    """Raised when a status transition is not allowed."""

    def __init__(
        self,
        rec_type: RecommendationType,
        from_status: RecommendationStatus,
        to_status: RecommendationStatus,
    ):
        self.rec_type = rec_type
        self.from_status = from_status
        self.to_status = to_status
        super().__init__(
            f"Illegal transition for {rec_type.value}: "
            f"{from_status.value} -> {to_status.value}"
        )


# ============================================================
# Allowed transitions per recommendation type
# ============================================================

_S = RecommendationStatus

ALLOWED_TRANSITIONS: dict[RecommendationType, dict[RecommendationStatus, set[RecommendationStatus]]] = {
    # INSIGHT: informational only, no user actions
    # Stays NEW until expired or withdrawn by agent
    RecommendationType.INSIGHT: {
        _S.NEW: {_S.EXPIRED, _S.WITHDRAWN},
    },

    # RECOMMENDATION: user can acknowledge or reject
    RecommendationType.RECOMMENDATION: {
        _S.NEW: {_S.ACKNOWLEDGED, _S.REJECTED, _S.WITHDRAWN, _S.EXPIRED},
        _S.ACKNOWLEDGED: {_S.IN_PROGRESS, _S.COMPLETED, _S.WITHDRAWN, _S.EXPIRED},
        _S.IN_PROGRESS: {_S.COMPLETED, _S.WITHDRAWN},
    },

    # ACTION: requires explicit approval before execution
    RecommendationType.ACTION: {
        _S.NEW: {_S.APPROVED, _S.REJECTED, _S.WITHDRAWN, _S.EXPIRED},
        _S.APPROVED: {_S.IN_PROGRESS, _S.WITHDRAWN},
        _S.IN_PROGRESS: {_S.COMPLETED, _S.WITHDRAWN},
    },
}


def validate_transition(
    rec_type: RecommendationType,
    from_status: RecommendationStatus,
    to_status: RecommendationStatus,
) -> None:
    """
    Validate that a status transition is legal.
    Raises IllegalTransitionError if not.

    Usage:
        validate_transition(
            RecommendationType.RECOMMENDATION,
            RecommendationStatus.NEW,
            RecommendationStatus.ACKNOWLEDGED,
        )  # OK

        validate_transition(
            RecommendationType.INSIGHT,
            RecommendationStatus.NEW,
            RecommendationStatus.APPROVED,
        )  # raises IllegalTransitionError
    """
    type_transitions = ALLOWED_TRANSITIONS.get(rec_type, {})
    allowed = type_transitions.get(from_status, set())

    if to_status not in allowed:
        raise IllegalTransitionError(rec_type, from_status, to_status)


def get_available_actions(
    rec_type: RecommendationType,
    current_status: RecommendationStatus,
) -> set[RecommendationStatus]:
    """
    Return set of statuses this recommendation can transition to.
    Used by API to show available buttons in plugin.

    Usage:
        actions = get_available_actions(
            RecommendationType.RECOMMENDATION,
            RecommendationStatus.NEW,
        )
        # returns {ACKNOWLEDGED, REJECTED, WITHDRAWN, EXPIRED}
    """
    type_transitions = ALLOWED_TRANSITIONS.get(rec_type, {})
    return type_transitions.get(current_status, set())
