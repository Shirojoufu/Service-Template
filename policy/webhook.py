"""Validating admission webhook for Deployments.

Rejects a Deployment unless every container:
  - is pinned to an explicit tag or digest (not `latest`, not bare/untagged)
  - has resource requests and limits set (cpu and memory)
and both the Deployment and its pod template carry a `team` label, so
ownership and RBAC (policy/rbac/) stay traceable. See docs/adr/0003 and
docs/adr/0004 for why this is a custom webhook rather than built-in CEL.
"""
from __future__ import annotations

from fastapi import FastAPI

app = FastAPI(title="paved-road-policy-webhook")


def _check_image_pinned(image: str) -> str | None:
    """Return an error message if `image` is not pinned, else None."""
    if "@" in image:  # digest reference, e.g. repo@sha256:...
        return None
    _repo, sep, tag = image.rpartition(":")
    if not sep:
        return f"image '{image}' has no tag; pin to a specific version or digest"
    if tag == "latest":
        return f"image '{image}' must not use the 'latest' tag; pin to a specific version or digest"
    return None


def _check_resources(container: dict) -> list[str]:
    name = container.get("name", "<unnamed>")
    resources = container.get("resources") or {}
    errors = []
    for field in ("requests", "limits"):
        values = resources.get(field) or {}
        for key in ("cpu", "memory"):
            if key not in values:
                errors.append(f"container '{name}' is missing resources.{field}.{key}")
    return errors


def validate_deployment(deployment: dict) -> list[str]:
    """Return a list of human-readable validation errors; empty if valid."""
    errors: list[str] = []

    labels = (deployment.get("metadata") or {}).get("labels") or {}
    if not labels.get("team"):
        errors.append("metadata.labels.team is required")

    template = (deployment.get("spec") or {}).get("template") or {}
    template_labels = (template.get("metadata") or {}).get("labels") or {}
    if not template_labels.get("team"):
        errors.append("spec.template.metadata.labels.team is required")

    containers = (template.get("spec") or {}).get("containers") or []
    if not containers:
        errors.append("spec.template.spec.containers must not be empty")

    for container in containers:
        name = container.get("name", "<unnamed>")
        image = container.get("image")
        if not image:
            errors.append(f"container '{name}' has no image")
        else:
            error = _check_image_pinned(image)
            if error:
                errors.append(error)
        errors.extend(_check_resources(container))

    return errors


@app.post("/validate")
async def validate(review: dict) -> dict:
    request = review.get("request") or {}
    obj = request.get("object") or {}

    errors = validate_deployment(obj)

    response = {"uid": request.get("uid"), "allowed": not errors}
    if errors:
        response["status"] = {"message": "; ".join(errors)}

    return {
        "apiVersion": "admission.k8s.io/v1",
        "kind": "AdmissionReview",
        "response": response,
    }


@app.get("/healthz")
def healthz() -> dict:
    return {"status": "ok"}
