"""Offline checks of the desired-state tree: what the base declares and what the project pins."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

import pytest
import yaml

from tests.support.shell import run

OVERLAY = "manifests/apps/web/overlays/local"


def render(root: Path, overlay: str = OVERLAY) -> dict[tuple[str, str], dict[str, Any]]:
    """Render an overlay with kustomize and index the objects by (kind, name)."""
    output = run(["kubectl", "kustomize", str(root / overlay)]).stdout
    documents = [doc for doc in yaml.safe_load_all(output) if doc]
    return {(doc["kind"], doc["metadata"]["name"]): doc for doc in documents}


@pytest.fixture(scope="module")
def objects(root: Path) -> dict[tuple[str, str], dict[str, Any]]:
    return render(root)


def test_the_overlay_renders_the_four_objects_of_the_lesson(
    objects: dict[tuple[str, str], dict[str, Any]],
) -> None:
    assert set(objects) == {
        ("Namespace", "web"),
        ("ConfigMap", "web-config"),
        ("Deployment", "web"),
        ("Service", "web"),
    }


def test_the_app_starts_with_two_replicas_and_the_greeting_hello(
    objects: dict[tuple[str, str], dict[str, Any]],
) -> None:
    assert objects[("Deployment", "web")]["spec"]["replicas"] == 2
    assert objects[("ConfigMap", "web-config")]["data"] == {"GREETING": "hello"}


def test_the_overlay_pins_the_application_image_by_version(
    objects: dict[tuple[str, str], dict[str, Any]],
) -> None:
    container = objects[("Deployment", "web")]["spec"]["template"]["spec"]["containers"][0]

    assert container["image"] == "plainround/web:1.0.0"


def test_the_container_runs_unprivileged_with_limits_and_probes(
    objects: dict[tuple[str, str], dict[str, Any]],
) -> None:
    pod = objects[("Deployment", "web")]["spec"]["template"]["spec"]
    container = pod["containers"][0]

    assert pod["securityContext"]["runAsNonRoot"] is True
    assert container["securityContext"]["readOnlyRootFilesystem"] is True
    assert container["securityContext"]["allowPrivilegeEscalation"] is False
    assert container["securityContext"]["capabilities"]["drop"] == ["ALL"]
    assert {"requests", "limits"} <= set(container["resources"])
    assert {"readinessProbe", "livenessProbe"} <= set(container)


def test_the_namespace_enforces_the_restricted_pod_security_level(
    objects: dict[tuple[str, str], dict[str, Any]],
) -> None:
    labels = objects[("Namespace", "web")]["metadata"]["labels"]

    assert labels["pod-security.kubernetes.io/enforce"] == "restricted"


def test_the_application_has_an_explicit_automated_block(root: Path) -> None:
    application = yaml.safe_load((root / "manifests/clusters/local/application.yaml").read_text())

    assert application["spec"]["syncPolicy"]["automated"] == {"prune": False, "selfHeal": False}
    assert application["spec"]["source"]["path"] == "apps/web/overlays/local"


def test_the_project_only_allows_this_repository_and_namespace(root: Path) -> None:
    project = yaml.safe_load((root / "manifests/clusters/local/project.yaml").read_text())

    assert [destination["namespace"] for destination in project["spec"]["destinations"]] == ["web"]
    assert project["spec"]["clusterResourceWhitelist"] == [{"group": "", "kind": "Namespace"}]


def test_the_argo_cd_version_in_the_kustomization_matches_versions_env(root: Path) -> None:
    pinned = re.search(r"argo-cd/(v[\d.]+)/", (root / "platform/argocd/kustomization.yaml").read_text())
    versions = dict(
        line.split("=", 1)
        for line in (root / "versions.env").read_text().splitlines()
        if "=" in line and line[0] != "#"
    )

    assert pinned is not None
    assert pinned.group(1) == versions["ARGOCD_VERSION"]


def test_every_image_the_manifests_use_is_pinned_to_a_version(root: Path) -> None:
    text = "".join(path.read_text() for path in (root / "manifests").rglob("*.yaml"))
    text += (root / "platform/git-server/git-server.yaml").read_text()
    images = re.findall(r"^\s*image:\s*(\S+)", text, flags=re.MULTILINE)

    assert images, "expected at least one image reference"
    assert all(":" in image and not image.endswith(":latest") for image in images)
