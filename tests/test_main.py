from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

def test_healthz():
    assert client.get("/healthz").json() == {"status": "ok"}

def test_hello():
    r = client.get("/hello/graham")
    assert r.status_code == 200
    assert "graham" in r.json()["message"]