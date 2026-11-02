"""A small read-mostly view of the cluster and of Argo CD's Application, through kubectl."""

from __future__ import annotations

import json
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from typing import Any

from tests.support.shell import CommandResult, run


@dataclass(frozen=True)
class ApplicationState:
    """What the controller reports about one Application."""

    sync_status: str
    health_status: str
    revision: str
    operation_phase: str
    operation_message: str
    history_revisions: tuple[str, ...]
    self_heal: bool
    prune: bool


class Kube:
    """kubectl pinned to one context, so a test can never touch another cluster."""

    def __init__(
        self,
        context: str,
        runner: Callable[..., CommandResult] = run,
    ) -> None:
        """Remember the kubectl context (for kind ``kind-<cluster>``); ``runner`` is replaceable in tests."""
        self.context = context
        self._runner = runner

    def kubectl(self, *args: str, check: bool = True) -> CommandResult:
        """Run kubectl against this context."""
        command: Sequence[str] = ["kubectl", "--context", self.context, *args]
        return self._runner(command, check=check, timeout=120)

    def get(self, kind: str, name: str, namespace: str | None = None) -> dict[str, Any]:
        """Return one object as parsed JSON; raises CommandError when it does not exist."""
        scope = ["-n", namespace] if namespace else []
        parsed: dict[str, Any] = json.loads(self.kubectl("get", kind, name, *scope, "-o", "json").stdout)
        return parsed

    def exists(self, kind: str, name: str, namespace: str | None = None) -> bool:
        """True when the object exists."""
        scope = ["-n", namespace] if namespace else []
        return self.kubectl("get", kind, name, *scope, check=False).returncode == 0

    def application(self, name: str) -> ApplicationState:
        """The controller's view of an Application in the ``argocd`` namespace."""
        application = self.get("application", name, "argocd")
        status = application.get("status", {})
        automated = application["spec"].get("syncPolicy", {}).get("automated", {})
        operation = status.get("operationState", {})
        return ApplicationState(
            sync_status=status.get("sync", {}).get("status", ""),
            health_status=status.get("health", {}).get("status", ""),
            revision=status.get("sync", {}).get("revision", ""),
            operation_phase=operation.get("phase", ""),
            operation_message=operation.get("message", ""),
            history_revisions=tuple(entry["revision"] for entry in status.get("history", [])),
            self_heal=bool(automated.get("selfHeal", False)),
            prune=bool(automated.get("prune", False)),
        )

    def deployment_replicas(self, namespace: str, name: str) -> int:
        """The replica count the Deployment currently asks for."""
        return int(self.get("deployment", name, namespace)["spec"]["replicas"])

    def deployment_image(self, namespace: str, name: str) -> str:
        """The image of the Deployment's first container."""
        return str(self.get("deployment", name, namespace)["spec"]["template"]["spec"]["containers"][0]["image"])

    def configmap_value(self, namespace: str, name: str, key: str) -> str:
        """One key of a ConfigMap."""
        return str(self.get("configmap", name, namespace)["data"][key])

    def field_managers(self, kind: str, name: str, namespace: str) -> set[str]:
        """The names recorded in managedFields: who has written to this object."""
        # kubectl leaves managedFields out of its output unless asked.
        text = self.kubectl("get", kind, name, "-n", namespace, "-o", "json", "--show-managed-fields").stdout
        managed = json.loads(text)["metadata"].get("managedFields", [])
        return {entry["manager"] for entry in managed}

    def get_through_service(self, namespace: str, service: str, path: str = "/") -> str:
        """GET a path of a Service through the API server's proxy (no port-forward needed)."""
        endpoint = f"/api/v1/namespaces/{namespace}/services/{service}:80/proxy{path}"
        return self.kubectl("get", "--raw", endpoint).stdout.strip()
