from __future__ import annotations

import json
from collections.abc import Sequence
from typing import Any

from tests.support.kube import Kube
from tests.support.shell import CommandError, CommandResult


class FakeKubectl:
    """Answers kubectl calls from a table of canned JSON, and records each command line."""

    def __init__(self, objects: dict[str, dict[str, Any]], raw: str = "") -> None:
        self.objects = objects
        self.raw = raw
        self.commands: list[Sequence[str]] = []

    def __call__(self, args: Sequence[str], *, check: bool = True, timeout: float = 0) -> CommandResult:
        self.commands.append(args)
        if "--raw" in args:
            return CommandResult(tuple(args), 0, self.raw + "\n", "")
        key = f"{args[args.index('get') + 1]}/{args[args.index('get') + 2]}"
        if key in self.objects:
            return CommandResult(tuple(args), 0, json.dumps(self.objects[key]), "")
        result = CommandResult(tuple(args), 1, "", "NotFound")
        if check:
            raise CommandError(result)
        return result


APPLICATION = {
    "spec": {"syncPolicy": {"automated": {"selfHeal": True, "prune": False}}},
    "status": {
        "sync": {"status": "Synced", "revision": "abc123"},
        "health": {"status": "Healthy"},
        "operationState": {"phase": "Succeeded", "message": "successfully synced"},
        "history": [{"revision": "aaa111"}, {"revision": "abc123"}],
    },
}
DEPLOYMENT = {
    "metadata": {"managedFields": [{"manager": "argocd-controller"}, {"manager": "kube-controller-manager"}]},
    "spec": {"replicas": 3, "template": {"spec": {"containers": [{"image": "plainround/web:1.0.0"}]}}},
}
CONFIGMAP = {"data": {"GREETING": "hello"}}


def kube_with(raw: str = "") -> tuple[Kube, FakeKubectl]:
    fake = FakeKubectl(
        {"application/web": APPLICATION, "deployment/web": DEPLOYMENT, "configmap/web-config": CONFIGMAP}, raw
    )
    return Kube("kind-test", runner=fake), fake


def test_application_state_is_read_from_status_and_spec() -> None:
    kube, _ = kube_with()

    state = kube.application("web")

    assert (state.sync_status, state.health_status, state.revision) == ("Synced", "Healthy", "abc123")
    assert state.history_revisions == ("aaa111", "abc123")
    assert state.self_heal is True
    assert state.prune is False
    assert state.operation_phase == "Succeeded"


def test_an_application_without_status_reads_as_empty_strings() -> None:
    fake = FakeKubectl({"application/web": {"spec": {}}})

    state = Kube("kind-test", runner=fake).application("web")

    assert (state.sync_status, state.health_status, state.history_revisions) == ("", "", ())
    assert state.self_heal is False


def test_deployment_and_configmap_fields() -> None:
    kube, _ = kube_with()

    assert kube.deployment_replicas("web", "web") == 3
    assert kube.deployment_image("web", "web") == "plainround/web:1.0.0"
    assert kube.configmap_value("web", "web-config", "GREETING") == "hello"
    assert kube.field_managers("deployment", "web", "web") == {"argocd-controller", "kube-controller-manager"}


def test_exists_is_false_for_a_missing_object_and_true_for_a_present_one() -> None:
    kube, _ = kube_with()

    assert kube.exists("configmap", "web-config", "web") is True
    assert kube.exists("configmap", "gone", "web") is False


def test_every_command_is_pinned_to_the_context() -> None:
    kube, fake = kube_with(raw="hello")

    assert kube.get_through_service("web", "web") == "hello"
    kube.deployment_replicas("web", "web")

    assert all(command[:3] == ["kubectl", "--context", "kind-test"] for command in fake.commands)
    assert "/api/v1/namespaces/web/services/web:80/proxy/" in fake.commands[0]
