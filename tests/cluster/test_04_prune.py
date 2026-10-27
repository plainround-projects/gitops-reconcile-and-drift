"""Lesson step 4: with prune off a deleted file leaves its object (flagged); with prune on it is removed."""

from __future__ import annotations

from tests.conftest import Runbook
from tests.support.kube import Kube

from .conftest import APP, NAMESPACE


def test_with_prune_off_the_object_stays_and_the_app_is_out_of_sync(kube: Kube, runbook: Runbook) -> None:
    output = runbook.script("runbook/04-prune.sh", "off")

    assert kube.exists("configmap", "web-config", NAMESPACE)
    assert kube.application(APP).sync_status == "OutOfSync"
    assert "ConfigMap/web-config" in output


def test_with_prune_on_the_object_is_removed(kube: Kube, runbook: Runbook) -> None:
    runbook.script("runbook/04-prune.sh", "on")

    assert not kube.exists("configmap", "web-config", NAMESPACE)
    assert kube.application(APP).sync_status == "Synced"


def test_git_revert_brings_the_object_back(kube: Kube, runbook: Runbook) -> None:
    runbook.script("runbook/04-prune.sh", "restore")

    assert kube.exists("configmap", "web-config", NAMESPACE)
    assert kube.application(APP).sync_status == "Synced"
