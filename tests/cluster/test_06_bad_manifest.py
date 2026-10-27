"""A manifest the schema refuses never reaches the cluster: the hook, then the API server, say no."""

from __future__ import annotations

from tests.conftest import Runbook
from tests.support.kube import Kube

from .conftest import APP, NAMESPACE


def test_an_invalid_manifest_is_refused_by_the_hook_and_by_the_api_server(kube: Kube, runbook: Runbook) -> None:
    replicas_before = kube.deployment_replicas(NAMESPACE, "web")

    output = runbook.script("runbook/06-bad-manifest.sh")

    assert "1. the pre-push hook refuses it" in output
    assert "replicas" in output
    assert "operation phase: Error" in output or "operation phase: Failed" in output
    assert kube.deployment_replicas(NAMESPACE, "web") == replicas_before
    state = kube.application(APP)
    assert (state.sync_status, state.health_status) == ("Synced", "Healthy")
