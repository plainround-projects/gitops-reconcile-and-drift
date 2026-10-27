"""Lesson step 1: the app appears without a kubectl apply, synced and healthy."""

from __future__ import annotations

from tests.conftest import Runbook
from tests.support.kube import Kube
from tests.support.waiting import wait_until

from .conftest import APP, NAMESPACE


def test_the_app_appears_synced_and_healthy_from_git(kube: Kube, runbook: Runbook) -> None:
    head = runbook.work_head()

    state = wait_until(
        "the app synced and healthy at the seeded commit",
        lambda: (s := kube.application(APP)).sync_status == "Synced" and s.health_status == "Healthy" and s,
        timeout=240,
    )

    assert state.revision == head


def test_the_workloads_were_written_by_the_controller_and_not_by_kubectl(kube: Kube) -> None:
    managers = kube.field_managers("deployment", "web", NAMESPACE)

    assert "argocd-controller" in managers
    assert not any(manager.startswith("kubectl") for manager in managers)


def test_two_pods_run_and_the_service_answers_with_the_greeting(kube: Kube) -> None:
    wait_until(
        "two ready replicas",
        lambda: kube.get("deployment", "web", NAMESPACE)["status"].get("readyReplicas") == 2,
        timeout=120,
    )

    assert kube.get_through_service(NAMESPACE, "web") == "hello"
    assert kube.get_through_service(NAMESPACE, "web", "/version") == "1.0.0"
