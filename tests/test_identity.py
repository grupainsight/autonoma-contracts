"""Conformance: the Python resolver must pass conformance/identity_vectors.json (same file as the SQL test)."""

import json
import os

import pytest

from autonoma_contracts.identity import IdentityError, identifier_map, normalize_domain, resolve_client_key

V = json.load(open(os.path.join(os.path.dirname(__file__), "..", "conformance", "identity_vectors.json")))


@pytest.mark.parametrize("raw,expected", V["normalize_domain"])
def test_normalize_domain(raw, expected):
    assert normalize_domain(raw) == expected


@pytest.mark.parametrize("kind,value,expected", V["resolve"])
def test_resolve(kind, value, expected):
    if expected == "ERROR":
        with pytest.raises(IdentityError):
            resolve_client_key(kind, value, V["profiles"])
    else:
        assert resolve_client_key(kind, value, V["profiles"]) == expected


@pytest.mark.parametrize("case", V["conflicts"])
def test_conflicting_identifiers_are_refused(case):
    with pytest.raises(IdentityError):
        identifier_map(case["profiles"])


def test_subdomain_is_not_collapsed():
    # a store on a subdomain is a different object until listed explicitly
    assert resolve_client_key("domain", "sklep.piccolotesoro.pl", V["profiles"]) is None
