"""Checks run against the real image, started by CI. BASE_URL and EXPECTED_VERSION come from the workflow."""
import json
import os
import time
import urllib.error
import urllib.request

BASE = os.environ["BASE_URL"]
EXPECTED = os.environ["EXPECTED_VERSION"]
RUN = str(time.time_ns())  # unique browser ids per run, so reruns never hit the rate limit


def call(path, body=None, cid="staging"):
    cid = f"{cid}-{RUN}"
    sep = "&" if "?" in path else "?"
    url = f"{BASE}{path}{sep}cid={cid}" if body is None else f"{BASE}{path}"
    data = None if body is None else json.dumps({"cid": cid, **body}).encode()
    req = urllib.request.Request(url, data, {"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, ""


def test_healthy():
    assert call("/healthz")[0] == 200


def test_page_shows_the_new_version():
    status, html = call("/")
    assert status == 200 and EXPECTED in html


def test_status_reports_the_new_version():
    assert json.loads(call("/api/status")[1])["version"] == EXPECTED


def test_vote_works():
    status, body = call("/api/vote", {"choice": "green"}, cid="voter1")
    assert status == 200 and json.loads(body)["votes"]["green"] >= 1


def test_bad_input_is_rejected():
    assert call("/api/vote", {"choice": "<script>"}, cid="voter2")[0] == 400
    assert call("/api/react", {"kind": "free text"}, cid="voter3")[0] == 400


def test_reset_is_protected():
    assert call("/admin/reset", {}, cid="voter4")[0] == 403
