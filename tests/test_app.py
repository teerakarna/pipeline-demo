import pytest

from app import main


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(main, "DB_PATH", str(tmp_path / "test.db"))
    monkeypatch.setattr(main, "MIN_GAP", 0)
    main._last_action.clear()
    return main.app.test_client()


def test_button_colour_is_allowed():
    assert main.BUTTON_COLOUR in main.ALLOWED_COLOURS


def test_page_renders(client):
    r = client.get("/")
    assert r.status_code == 200
    assert main.VERSION.encode() in r.data


def test_vote_counts_and_replaces(client):
    client.post("/api/vote", json={"cid": "a", "choice": "green"})
    client.post("/api/vote", json={"cid": "a", "choice": "blue"})
    s = client.post("/api/vote", json={"cid": "b", "choice": "blue"}).get_json()
    assert s["votes"]["blue"] == 2 and s["votes"]["green"] == 0


def test_only_fixed_choices(client):
    assert client.post("/api/vote", json={"cid": "a", "choice": "<script>"}).status_code == 400
    assert client.post("/api/react", json={"cid": "a", "kind": "hello"}).status_code == 400


def test_connected_count_from_heartbeats(client):
    client.get("/api/status?cid=a")
    s = client.get("/api/status?cid=b").get_json()
    assert s["online"] == 2


def test_reset_needs_token(client, monkeypatch):
    client.post("/api/vote", json={"cid": "a", "choice": "blue"})
    assert client.post("/admin/reset").status_code == 403
    monkeypatch.setenv("RESET_TOKEN", "t")
    assert client.post("/admin/reset", headers={"X-Reset-Token": "wrong"}).status_code == 403
    assert client.post("/admin/reset", headers={"X-Reset-Token": "t"}).status_code == 200
    assert client.get("/api/status?cid=a").get_json()["votes"]["blue"] == 0


def test_rate_limit(client, monkeypatch):
    monkeypatch.setattr(main, "MIN_GAP", 60)
    monkeypatch.setattr(main.time, "monotonic", lambda: 1000.0)  # fixed clock: no dependence on machine uptime
    assert client.post("/api/react", json={"cid": "a", "kind": "clap"}).status_code == 200
    assert client.post("/api/react", json={"cid": "a", "kind": "clap"}).status_code == 429
