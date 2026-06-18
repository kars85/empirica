"""Tests for the opt-in hard Qdrant requirement gate at project-bootstrap.

EMPIRICA_REQUIRE_QDRANT=true makes a session refuse to bootstrap unless Qdrant
is reachable AND the project's docs collection has indexed points. Unset (the
default) is a strict no-op so the rest of the suite and headless/CI runs that
have no Qdrant are unaffected.

Surface tested: project_bootstrap._enforce_qdrant_requirement
  - flag unset            -> proceed (False), never touches Qdrant
  - flag set, no client   -> blocked (True)
  - flag set, no collection -> blocked (True)
  - flag set, empty collection (0 points) -> blocked (True)
  - flag set, populated collection -> proceed (False)
"""

from __future__ import annotations

from unittest.mock import MagicMock, patch

from empirica.cli.command_handlers import project_bootstrap as pb

PROJECT_ID = "a8e00884-006b-4a50-b3e1-b4ade79beab7"
DOCS_COLLECTION = f"project_{PROJECT_ID}_docs"


def _client_with_points(points: int, *, exists: bool = True) -> MagicMock:
    client = MagicMock()
    client.collection_exists.return_value = exists
    client.get_collection.return_value = MagicMock(points_count=points)
    return client


def test_gate_disabled_is_noop_and_never_probes_qdrant(monkeypatch):
    monkeypatch.delenv("EMPIRICA_REQUIRE_QDRANT", raising=False)
    with patch("empirica.core.qdrant.connection._get_qdrant_client") as mock_client:
        blocked = pb._enforce_qdrant_requirement(PROJECT_ID, "json")
    assert blocked is False
    mock_client.assert_not_called()


def test_gate_blocks_when_server_unreachable(monkeypatch):
    monkeypatch.setenv("EMPIRICA_REQUIRE_QDRANT", "true")
    with patch("empirica.core.qdrant.connection._get_qdrant_client", return_value=None):
        blocked = pb._enforce_qdrant_requirement(PROJECT_ID, "json")
    assert blocked is True


def test_gate_blocks_when_docs_collection_missing(monkeypatch):
    monkeypatch.setenv("EMPIRICA_REQUIRE_QDRANT", "true")
    client = _client_with_points(0, exists=False)
    with patch("empirica.core.qdrant.connection._get_qdrant_client", return_value=client):
        blocked = pb._enforce_qdrant_requirement(PROJECT_ID, "json")
    assert blocked is True
    client.collection_exists.assert_called_once_with(DOCS_COLLECTION)


def test_gate_blocks_when_collection_empty(monkeypatch):
    monkeypatch.setenv("EMPIRICA_REQUIRE_QDRANT", "true")
    client = _client_with_points(0)
    with patch("empirica.core.qdrant.connection._get_qdrant_client", return_value=client):
        blocked = pb._enforce_qdrant_requirement(PROJECT_ID, "json")
    assert blocked is True


def test_gate_proceeds_when_collection_populated(monkeypatch):
    monkeypatch.setenv("EMPIRICA_REQUIRE_QDRANT", "true")
    client = _client_with_points(31)
    with patch("empirica.core.qdrant.connection._get_qdrant_client", return_value=client):
        blocked = pb._enforce_qdrant_requirement(PROJECT_ID, "json")
    assert blocked is False


def test_gate_blocks_when_inspection_raises(monkeypatch):
    monkeypatch.setenv("EMPIRICA_REQUIRE_QDRANT", "true")
    client = MagicMock()
    client.collection_exists.side_effect = RuntimeError("transport error")
    with patch("empirica.core.qdrant.connection._get_qdrant_client", return_value=client):
        blocked = pb._enforce_qdrant_requirement(PROJECT_ID, "json")
    assert blocked is True


def test_flag_is_case_insensitive_and_trimmed(monkeypatch):
    monkeypatch.setenv("EMPIRICA_REQUIRE_QDRANT", "  TRUE  ")
    with patch("empirica.core.qdrant.connection._get_qdrant_client", return_value=None):
        blocked = pb._enforce_qdrant_requirement(PROJECT_ID, "json")
    assert blocked is True
