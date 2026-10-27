"""Every cluster test module starts from the first state of the lesson."""

from __future__ import annotations

from pathlib import Path

import pytest

from tests.conftest import Runbook
from tests.support.kube import Kube

APP = "web"
NAMESPACE = "web"


@pytest.fixture(scope="module", autouse=True)
def clean_demo(root: Path, kube: Kube) -> None:
    """Delete the demo, reseed the repository and let the controller deploy it again."""
    Runbook(root).script("reset.sh")
