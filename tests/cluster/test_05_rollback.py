"""Lesson step 5: a bad commit degrades the app; git revert restores the previous image with no kubectl."""

from __future__ import annotations

from tests.conftest import Runbook
from tests.support.kube import Kube

from .conftest import APP, NAMESPACE

PREVIOUS_IMAGE = "plainround/web:1.0.0"
BAD_IMAGE = "plainround/web:1.1.0"


def test_the_bad_commit_makes_the_controller_report_degraded_while_old_pods_keep_serving(
    kube: Kube, runbook: Runbook
) -> None:
    runbook.script("runbook/05-break-and-rollback.sh", "bad")

    assert kube.application(APP).health_status == "Degraded"
    assert kube.deployment_image(NAMESPACE, "web") == BAD_IMAGE
    assert kube.get_through_service(NAMESPACE, "web", "/version") == "1.0.0"


def test_git_revert_restores_the_previous_image_and_health(kube: Kube, runbook: Runbook) -> None:
    runbook.script("runbook/05-break-and-rollback.sh", "rollback")

    state = kube.application(APP)
    assert state.health_status == "Healthy"
    assert state.sync_status == "Synced"
    assert state.revision == runbook.work_head()
    assert kube.deployment_image(NAMESPACE, "web") == PREVIOUS_IMAGE
    assert kube.get_through_service(NAMESPACE, "web", "/version") == "1.0.0"
