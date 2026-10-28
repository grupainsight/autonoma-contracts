import re
from datetime import date, datetime, UTC
from pathlib import Path

import pytest
from pydantic import ValidationError

from autonoma_contracts.merchant_performance import (
    PerformancePeriod, ProductPerformanceRow, completeness, last_complete_week, week_start,
)

SQL = (Path(__file__).parent.parent / "sql" / "005_merchant_product_performance.sql").read_text()


def _columns(table):
    body = re.search(rf"CREATE TABLE IF NOT EXISTS {table} \((.*?)\n\);", SQL, re.S).group(1)
    cols = set()
    for line in body.splitlines():
        m = re.match(r"\s+([a-z_][a-z0-9_]*)\s+[A-Z]", line)
        if m and m.group(1) not in ("id", "created_at", "updated_at"):
            cols.add(m.group(1))
    return cols


@pytest.mark.parametrize("table, model", [
    ("merchant_product_performance", ProductPerformanceRow),
    ("merchant_performance_periods", PerformancePeriod),
])
def test_model_matches_sql(table, model):
    assert _columns(table) == set(model.model_fields)


def test_weeks():
    assert week_start(date(2026, 10, 28)) == date(2026, 10, 26)
    assert last_complete_week(date(2026, 11, 3)) == date(2026, 10, 26)   # Tuesday run
    assert last_complete_week(date(2026, 11, 2)) == date(2026, 10, 26)   # Monday run
    assert last_complete_week(date(2026, 11, 1)) == date(2026, 10, 19)   # Sunday: week not over
    assert last_complete_week(date(2027, 1, 5)) == date(2026, 12, 28)    # across the year


def _row(**kw):
    base = dict(client_key="piccolotesoro", merchant_id="1", period_start=date(2026, 10, 19),
                period_end=date(2026, 10, 25), offer_id="98707", marketing_method="ADS",
                impressions=10, clicks=1, in_current_catalog=True, fetch_id="f")
    return ProductPerformanceRow(**{**base, **kw})


def test_row_rules():
    assert _row().marketing_method.value == "ADS"
    for bad in (dict(period_start=date(2026, 10, 20), period_end=date(2026, 10, 26)),
                dict(period_end=date(2026, 10, 24)), dict(offer_id=""),
                dict(marketing_method="ADS_AND_ORGANIC"), dict(clicks=-1)):
        with pytest.raises(ValidationError):
            _row(**bad)


def test_completeness():
    assert completeness(86454, 115774) == 0.7467
    assert completeness(0, 0) is None
