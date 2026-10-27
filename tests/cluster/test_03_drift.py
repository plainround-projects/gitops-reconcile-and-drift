"""Lesson step 3: drift is reported with self-heal off and reverted with it on."""

from __future__ import annotations

from tests.conftest import Runbook
from tests.support.kube import Kube
from tests.support.waiting import wait_until

from .conftest import APP, NAMESPACE


def test_with_self_heal_off_the_drift_is_reported_and_left_alone(kube: Kube, runbook: Runbook) -> None:
    runbook.script("runbook/02-change-through-git.sh")

    output = runbook.script("runbook/03-drift.sh", "off")

    assert kube.deployment_replicas(NAMESPACE, "web") == 5
    assert kube.configmap_value(NAMESPACE, "web-config", "GREETING") == "hacked"
    assert kube.application(APP).sync_status == "OutOfSync"
    assert not kube.application(APP).self_heal
    assert "+  replicas: 5" in output or "replicas: 5" in output
    assert "GREETING: hacked" in output


def test_with_self_heal_on_both_changes_are_reverted_without_a_command(kube: Kube, runbook: Runbook) -> None:
    output = runbook.script("runbook/03-drift.sh", "on")

    wait_until(
        "the app to be Synced",
        lambda: kube.application(APP).sync_status == "Synced",
        timeout=60,
    )
    assert kube.deployment_replicas(NAMESPACE, "web") == 3
    assert kube.configmap_value(NAMESPACE, "web-config", "GREETING") == "hi there"
    assert kube.application(APP).self_heal
    assert "reverted in" in output
