import httpx
import respx
from fastapi.testclient import TestClient

from app.main import create_app

BASE = "https://api.aniskip.com/v2"
PAYLOAD = {
    "found": True,
    "results": [{"interval": {"startTime": 90, "endTime": 180}, "skipType": "op",
                 "skipId": "x", "episodeLength": 1440}],
    "message": "ok",
}


@respx.mock
def test_health_and_skip_times():
    respx.get(f"{BASE}/skip-times/5114/10").mock(return_value=httpx.Response(200, json=PAYLOAD))
    with TestClient(create_app()) as client:
        assert client.get("/health").json()["status"] == "ok"

        r = client.get("/api/v1/skip-times/5114/10", params={"types": "op,ed"})
        body = r.json()
        assert r.status_code == 200
        assert body["found"] is True and body["source"] == "aniskip"
        assert body["segments"][0] == {
            "type": "op", "start": 90.0, "end": 180.0,
            "source": "aniskip", "confidence": 1.0, "skip_id": "x",
        }


@respx.mock
def test_aniskip_down_returns_graceful_response():
    respx.get(f"{BASE}/skip-times/1/1").mock(side_effect=httpx.ConnectError("offline"))
    with TestClient(create_app()) as client:
        body = client.get("/api/v1/skip-times/1/1").json()
        assert body["found"] is False
        assert "indisponible" in body["message"]


def test_bad_type_is_rejected():
    with TestClient(create_app()) as client:
        assert client.get("/api/v1/skip-times/1/1", params={"types": "intro"}).status_code == 422


def test_analyze_rejects_path_traversal():
    with TestClient(create_app()) as client:
        r = client.post("/api/v1/analyze", json={"target": "../../etc/passwd", "references": ["a.mkv"]})
        assert r.json()["found"] is False
        assert "refusé" in r.json()["message"]
