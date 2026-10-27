"""Step 6: the same three behaviors on Flux, so the README's comparison table rests on a run, not on reading."""

from __future__ import annotations

import pytest

from tests.conftest import Runbook

pytestmark = pytest.mark.compare


@pytest.fixture(scope="module")
def results(runbook_module: Runbook) -> dict[str, str]:
    output = runbook_module.script("compare/flux-behaviors.sh", timeout=1200)
    lines = [line.removeprefix("RESULT ") for line in output.splitlines() if line.startswith("RESULT ")]
    return {line.split(":", 1)[0]: line for line in lines}


def test_flux_reverts_drift_with_no_self_heal_setting(results: dict[str, str]) -> None:
    assert "replicas 5 -> 2" in results["drift"]
    assert "hacked -> hello" in results["drift"]


def test_flux_leaves_a_deleted_object_alone_until_prune_is_on(results: dict[str, str]) -> None:
    assert "ConfigMap present" in results["prune-off"]
    assert "Ready=True" in results["prune-off"]
    assert "gone after spec.prune=true" in results["prune-on"]


def test_flux_reports_an_unhealthy_rollout_as_not_ready_and_recovers_on_revert(results: dict[str, str]) -> None:
    assert "Ready=False" in results["health"]
    assert "Ready=True" in results["rollback"]
    assert "plainround/web:1.0.0" in results["rollback"]
