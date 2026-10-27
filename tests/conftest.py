"""Fixtures shared by the cluster tests."""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from tests.support.kube import Kube
from tests.support.shell import run

ROOT = Path(__file__).resolve().parent.parent


def pytest_collection_modifyitems(items: list[pytest.Item]) -> None:
    """Tests under tests/cluster are marked ``cluster`` so `-m "not cluster"` runs the offline ones."""
    for item in items:
        if "tests/cluster" in str(item.fspath).replace(os.sep, "/"):
            item.add_marker(pytest.mark.cluster)


@pytest.fixture(scope="session")
def root() -> Path:
    """The repository root."""
    return ROOT


@pytest.fixture(scope="session")
def cluster_name() -> str:
    """The kind cluster this project owns."""
    return os.environ.get("CLUSTER_NAME", "gitops-drift")


def context_of(cluster_name: str) -> str:
    """The kubectl context of the cluster: k3d's or kind's, whichever `make up` created."""
    contexts = run(["kubectl", "config", "get-contexts", "-o", "name"], check=False).stdout.split()
    for candidate in (f"k3d-{cluster_name}", f"kind-{cluster_name}"):
        if candidate in contexts:
            return candidate
    pytest.fail(f"no kubectl context for cluster {cluster_name}: run `make up` first", pytrace=False)


@pytest.fixture(scope="session")
def kube(cluster_name: str) -> Kube:
    """kubectl pinned to the project's cluster; the tests need `make up` to have run."""
    client = Kube(context_of(cluster_name))
    if client.kubectl("get", "namespace", "argocd", check=False).returncode != 0:
        pytest.fail("the cluster is not up: run `make up` first", pytrace=False)
    return client


@pytest.fixture(scope="module")
def runbook_module(root: Path) -> Runbook:
    """The same as ``runbook``, for fixtures that live for a whole module."""
    return Runbook(root)


@pytest.fixture
def runbook(root: Path) -> Runbook:
    """Run the repository's scripts from the repository root."""
    return Runbook(root)


class Runbook:
    """Calls the scripts under scripts/ (the same ones a person runs) and returns what they printed."""

    def __init__(self, root: Path) -> None:
        """Remember where the scripts live."""
        self.root = root

    def script(self, relative: str, *args: str, check: bool = True, timeout: float = 600) -> str:
        """Run ``scripts/<relative>``; return its combined output."""
        result = run([str(self.root / "scripts" / relative), *args], cwd=self.root, check=check, timeout=timeout)
        return result.output

    def work_head(self) -> str:
        """The commit at the tip of the working clone."""
        return run(["git", "-C", str(self.root / ".work" / "gitops-demo"), "rev-parse", "HEAD"]).stdout.strip()
