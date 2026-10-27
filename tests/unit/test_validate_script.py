"""scripts/validate.sh is the gate for 'a bad manifest is refused'; prove it can say no."""

from __future__ import annotations

import shutil
from pathlib import Path

import pytest

from tests.support.shell import run

pytestmark = pytest.mark.skipif(shutil.which("kubeconform") is None, reason="kubeconform is not installed")


def copy_tree(root: Path, target: Path) -> Path:
    shutil.copytree(root / "manifests", target)
    return target


def test_the_shipped_manifests_pass(root: Path, tmp_path: Path) -> None:
    result = run([str(root / "scripts/validate.sh"), str(copy_tree(root, tmp_path / "ok"))], check=False)

    assert result.returncode == 0, result.output


def test_a_string_where_a_number_belongs_is_refused(root: Path, tmp_path: Path) -> None:
    tree = copy_tree(root, tmp_path / "string-replicas")
    deployment = tree / "apps/web/base/deployment.yaml"
    deployment.write_text(deployment.read_text().replace("replicas: 2", 'replicas: "many"'))

    result = run([str(root / "scripts/validate.sh"), str(tree)], check=False)

    assert result.returncode != 0
    assert "replicas" in result.output


def test_an_unknown_field_is_refused(root: Path, tmp_path: Path) -> None:
    tree = copy_tree(root, tmp_path / "unknown-field")
    deployment = tree / "apps/web/base/deployment.yaml"
    deployment.write_text(deployment.read_text().replace("  replicas: 2", "  replicas: 2\n  replica_count: 3"))

    result = run([str(root / "scripts/validate.sh"), str(tree)], check=False)

    assert result.returncode != 0
    assert "replica_count" in result.output


def test_an_application_with_a_misspelled_field_is_refused(root: Path, tmp_path: Path) -> None:
    tree = copy_tree(root, tmp_path / "bad-application")
    application = tree / "clusters/local/application.yaml"
    application.write_text(application.read_text().replace("selfHeal", "selfHeel"))

    result = run([str(root / "scripts/validate.sh"), str(tree)], check=False)

    assert result.returncode != 0
