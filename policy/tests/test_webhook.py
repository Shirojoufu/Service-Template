"""AdmissionReview tests for the /validate webhook."""
import json
from pathlib import Path

from fastapi.testclient import TestClient

from policy.webhook import app

FIXTURES = Path(__file__).parent / "fixtures"
client = TestClient(app)


def _review(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text())


def test_good_deployment_is_allowed():
    review = _review("good-deployment.json")

    resp = client.post("/validate", json=review)

    assert resp.status_code == 200
    response = resp.json()["response"]
    assert response["uid"] == review["request"]["uid"]
    assert response["allowed"] is True
    assert "status" not in response


def test_bad_deployment_is_rejected():
    review = _review("bad-deployment.json")

    resp = client.post("/validate", json=review)

    assert resp.status_code == 200
    response = resp.json()["response"]
    assert response["uid"] == review["request"]["uid"]
    assert response["allowed"] is False

    message = response["status"]["message"]
    assert "metadata.labels.team" in message
    assert "spec.template.metadata.labels.team" in message
    assert "latest" in message
    assert "resources.requests.cpu" in message
    assert "resources.limits.memory" in message


def test_healthz():
    assert client.get("/healthz").json() == {"status": "ok"}
