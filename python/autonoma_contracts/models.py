"""
Autonoma Platform - Shared Pydantic models.

All agents import these to ensure consistent data structures.
Matches JSON schemas in /schemas and SQL in /sql.
"""

from datetime import date, datetime
from enum import Enum
from typing import Any, Optional

from pydantic import BaseModel, Field


# ============================================================
# Enums
# ============================================================

class ModuleName(str, Enum):
    ADS = "ads"
    SEO = "seo"
    GBP = "gbp"
    MERCHANT = "merchant"


class ModuleStatus(str, Enum):
    OK = "ok"
    WARNING = "warning"
    CRITICAL = "critical"
    ERROR = "error"
    NO_DATA = "no_data"


class RecommendationType(str, Enum):
    INSIGHT = "INSIGHT"
    RECOMMENDATION = "RECOMMENDATION"
    ACTION = "ACTION"


class RecommendationStatus(str, Enum):
    NEW = "NEW"
    ACKNOWLEDGED = "ACKNOWLEDGED"
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"
    IN_PROGRESS = "IN_PROGRESS"
    COMPLETED = "COMPLETED"
    WITHDRAWN = "WITHDRAWN"
    EXPIRED = "EXPIRED"


class Impact(str, Enum):
    LOW = "LOW"
    MEDIUM = "MEDIUM"
    HIGH = "HIGH"
    CRITICAL = "CRITICAL"


class ActorType(str, Enum):
    AGENT = "AGENT"
    CLIENT_USER = "CLIENT_USER"
    GI_USER = "GI_USER"
    SYSTEM = "SYSTEM"


class EventSource(str, Enum):
    AGENT = "agent"
    PLUGIN = "plugin"
    EMAIL = "email"
    API = "api"
    SYSTEM = "system"


class RunStatus(str, Enum):
    RUNNING = "RUNNING"
    SUCCESS = "SUCCESS"
    PARTIAL = "PARTIAL"
    FAILED = "FAILED"
    SKIPPED = "SKIPPED"


class JobType(str, Enum):
    WEEKLY = "weekly"
    DAILY = "daily"
    ON_DEMAND = "on_demand"


# ============================================================
# Dashboard Module
# ============================================================

class SourceFreshness(BaseModel):
    """Per-source freshness tracking. API computes 'stale' at read time."""
    last_successful_run: datetime
    stale_after_seconds: int = Field(
        description="2x normal interval. Weekly=1209600, daily=172800"
    )


class DataPeriod(BaseModel):
    from_date: date = Field(alias="from")
    to_date: date = Field(alias="to")

    model_config = {"populate_by_name": True}


class TopIssue(BaseModel):
    title: str
    impact: Impact


class DashboardModule(BaseModel):
    """
    Standard output contract for every Autonoma agent.
    Agent writes this to agent_dashboard_modules via upsert on (client_id, module).
    Field 'stale' is NOT stored - computed by API at read time.
    """
    module: ModuleName
    status: ModuleStatus
    summary: str = Field(max_length=200)
    last_successful_run: datetime
    data_period: DataPeriod
    sources: dict[str, SourceFreshness]
    confidence: int = Field(ge=0, le=100)
    metrics: dict[str, Any] = Field(default_factory=dict)
    top_issue: Optional[TopIssue] = None


# ============================================================
# Recommendation
# ============================================================

class Evidence(BaseModel):
    source: str
    data: dict[str, Any]


class Recommendation(BaseModel):
    """
    Unified recommendation record produced by any agent.
    Supports deduplication via dedupe_key.
    """
    id: str
    client_id: str
    source_agent: ModuleName
    type: RecommendationType
    status: RecommendationStatus = RecommendationStatus.NEW
    title: str = Field(max_length=200)
    summary: str = Field(max_length=1000)
    recommended_action: Optional[str] = Field(None, max_length=1000)
    impact: Impact
    confidence: int = Field(ge=0, le=100)
    reason_codes: list[str] = Field(default_factory=list)
    evidence: list[Evidence] = Field(default_factory=list)
    requires_approval: bool = False
    # Deduplication
    dedupe_key: str = Field(max_length=500)
    subject_key: Optional[str] = None
    first_seen_at: datetime
    last_seen_at: datetime
    occurrence_count: int = Field(ge=1, default=1)
    resolved_at: Optional[datetime] = None
    supersedes_recommendation_id: Optional[str] = None
    # Lifecycle
    expires_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime

    def model_post_init(self, __context: Any) -> None:
        """Validate that INSIGHTs have expires_at."""
        if self.type == RecommendationType.INSIGHT and self.expires_at is None:
            raise ValueError("INSIGHT recommendations must have expires_at set")


# ============================================================
# Recommendation Event
# ============================================================

class RecommendationEvent(BaseModel):
    """Audit trail for every status change on a recommendation."""
    id: str
    recommendation_id: str
    previous_status: RecommendationStatus
    new_status: RecommendationStatus
    actor_type: ActorType
    actor_id: Optional[str] = None
    source: EventSource
    comment: Optional[str] = Field(None, max_length=1000)
    created_at: datetime


# ============================================================
# Agent Run
# ============================================================

class AgentRun(BaseModel):
    """
    Record of every agent execution.
    Tracks timing, status, LLM usage and cost.
    """
    id: str
    client_id: str
    agent: ModuleName
    job_type: JobType
    scheduled_for: Optional[datetime] = None
    started_at: datetime
    completed_at: Optional[datetime] = None
    status: RunStatus
    error_code: Optional[str] = None
    error_message: Optional[str] = Field(None, max_length=2000)
    input_records: Optional[int] = None
    output_records: Optional[int] = None
    llm_used: bool = False
    input_tokens: Optional[int] = None
    output_tokens: Optional[int] = None
    llm_cost_usd: Optional[float] = None
    created_at: datetime
