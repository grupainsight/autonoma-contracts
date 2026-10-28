"""
Autonoma Platform - Merchant product performance (sql/005_merchant_product_performance.sql).

Weekly (Monday-Sunday) paid / free traffic per offer from Merchant Reports API.
See docs/merchant-product-performance.md for the reading rules:
- a week counts only when published in merchant_performance_periods, and only
  rows with the period's fetch_id belong to it;
- a missing offer row is not zero; per-offer values are a lower bound, channel
  totals and completeness live in the period row;
- ADS and ORGANIC are never added up;
- current_product_url / in_current_catalog describe the load's catalog snapshot.
"""

from datetime import date, datetime, timedelta
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field, model_validator


class MarketingMethod(str, Enum):
    ADS = "ADS"
    ORGANIC = "ORGANIC"


def week_start(day: date) -> date:
    """Monday of the ISO week containing `day`."""
    return day - timedelta(days=day.weekday())


def last_complete_week(run_date: date) -> date:
    """Monday of the last Monday-Sunday week that ended before `run_date`."""
    return week_start(run_date) - timedelta(days=7)


class _Week(BaseModel):
    period_start: date
    period_end: date

    @model_validator(mode="after")
    def _check_week(self):
        if self.period_start.weekday() != 0:
            raise ValueError("period_start must be a Monday")
        if self.period_end != self.period_start + timedelta(days=6):
            raise ValueError("period_end must be period_start + 6 days")
        return self


class ProductPerformanceRow(_Week):
    client_key: str
    merchant_id: str
    offer_id: str = Field(min_length=1)
    marketing_method: MarketingMethod
    impressions: int = Field(ge=0)
    clicks: int = Field(ge=0)
    current_product_url: Optional[str] = None
    in_current_catalog: bool
    fetch_id: str


class PerformancePeriod(_Week):
    client_key: str
    merchant_id: str
    fetch_id: str
    fetched_at: datetime
    run_id: Optional[str] = None
    catalog_snapshot_date: Optional[date] = None
    ads_impressions: int = Field(ge=0)
    ads_clicks: int = Field(ge=0)
    organic_impressions: int = Field(ge=0)
    organic_clicks: int = Field(ge=0)
    ads_impressions_by_offer: int = Field(ge=0)
    ads_clicks_by_offer: int = Field(ge=0)
    organic_impressions_by_offer: int = Field(ge=0)
    organic_clicks_by_offer: int = Field(ge=0)
    offer_rows: int = Field(ge=0)
    offers: int = Field(ge=0)
    rows_without_offer: int = Field(ge=0)
    rows_unknown_method: int = Field(ge=0)


def completeness(by_offer: int, total: int) -> Optional[float]:
    """Share of a channel total visible in per-offer rows; None when the total is 0."""
    if total <= 0:
        return None
    return round(by_offer / total, 4)
