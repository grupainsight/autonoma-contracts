import json
import os
from datetime import datetime, timezone

import pytest

from autonoma_contracts.mutation import MutationRequest, Policy, check
from autonoma_contracts.toolcall import record, redact_params

V = json.load(open(os.path.join(os.path.dirname(__file__), "..", "conformance", "mutation_vectors.json")))


@pytest.mark.parametrize("case", V["cases"], ids=[c["name"] for c in V["cases"]])
def test_mutation_policy_vectors(case):
    req = MutationRequest(**{**V["base"], **case["req"]})
    out = check(req, Policy(**V["policy"]), case["state"], case["owner"], set(case.get("seen", [])))
    assert [out[0].value, out[1]] == case["expect"]


def test_tool_call_record_is_redacted():
    r = record(agent="seo", agent_version="v2", client_key="spcg", run_id="r1", tool="get_top_queries",
               params={"days": 28, "limit": 50, "query": "kancelaria Jan Kowalski 600100200", "api_key": "sk-123"},
               ok=False, error=RuntimeError("401 for jan.kowalski@spcg.pl"), sources=["api:gsc", "api:gsc"],
               started_at=datetime(2026, 10, 18, tzinfo=timezone.utc))
    dumped = json.dumps(r)
    for secret in ("sk-123", "Kowalski", "600100200", "jan.kowalski"):
        assert secret not in dumped
    assert r["params"]["safe"] == {"days": 28, "limit": 50}
    assert r["params"]["keys"] == ["api_key", "days", "limit", "query"]
    assert r["status"] == "ERROR" and r["error_class"] == "RuntimeError" and r["sources"] == ["api:gsc"]


def test_tool_call_error_text_is_not_kept():
    assert record(agent="a", agent_version="1", client_key="c", run_id="r", tool="t", params={}, ok=False,
                  error="client 4963641094 has no data for Jan")["error_class"] == "ERROR"
    assert record(agent="a", agent_version="1", client_key="c", run_id="r", tool="t", params={}, ok=False,
                  error="TIMEOUT")["error_class"] == "TIMEOUT"


def test_tool_call_needs_a_client_and_hash_is_stable():
    with pytest.raises(ValueError):
        record(agent="a", agent_version="1", client_key="", run_id="r", tool="t", params={}, ok=True)
    assert redact_params({"b": 1, "a": 2})["sha256"] == redact_params({"a": 2, "b": 1})["sha256"]
