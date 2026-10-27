"""Lesson step 2: a commit reaches the cluster, and every running object can be traced to a commit."""

from __future__ import annotations

from tests.conftest import Runbook
from tests.support.kube import Kube

from .conftest import APP, NAMESPACE


def test_a_commit_scales_the_app_and_changes_the_greeting(kube: Kube, runbook: Runbook) -> None:
    output = runbook.script("runbook/02-change-through-git.sh")

    assert kube.deployment_replicas(NAMESPACE, "web") == 3
    assert kube.configmap_value(NAMESPACE, "web-config", "GREETING") == "hi there"
    assert "GREETING:  hi there" in output
    assert kube.get_through_service(NAMESPACE, "web") == "hi there"


def test_the_running_objects_name_the_commit_they_came_from(kube: Kube, runbook: Runbook) -> None:
    state = kube.application(APP)

    assert state.revision == runbook.work_head()
    assert state.history_revisions[-1] == runbook.work_head()
    assert len(state.history_revisions) >= 2
