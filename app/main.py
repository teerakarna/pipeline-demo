"""Live pipeline demo: a tiny voting page. One file, on purpose."""
import os
import socket
import sqlite3
import time

from flask import Flask, abort, jsonify, render_template, request

# The live change in the talk is this one line.
BUTTON_COLOUR = "blue"
ALLOWED_COLOURS = ["blue", "green", "orange", "purple"]
REACTIONS = ["clap", "fire", "mind-blown"]

VERSION = os.environ.get("APP_VERSION", "v1")
POD = os.environ.get("HOSTNAME") or socket.gethostname()
DB_PATH = os.environ.get("DB_PATH", "demo.db")
ONLINE_WINDOW = 6  # seconds: a browser counts as connected if seen this recently
MIN_GAP = 0.3      # seconds between actions from one browser (per copy)

app = Flask(__name__)
_last_action = {}


def db():
    con = sqlite3.connect(DB_PATH, timeout=5)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA journal_mode=WAL")
    con.executescript(
        """
        CREATE TABLE IF NOT EXISTS seen (cid TEXT PRIMARY KEY, at REAL);
        CREATE TABLE IF NOT EXISTS votes (cid TEXT PRIMARY KEY, choice TEXT);
        CREATE TABLE IF NOT EXISTS reactions (kind TEXT PRIMARY KEY, n INTEGER);
        """
    )
    return con


def client_id():
    cid = request.args.get("cid") or (request.get_json(silent=True) or {}).get("cid", "")
    cid = str(cid)[:40]
    if not cid:
        abort(400)
    return cid


def throttle(cid):
    now = time.monotonic()
    if now - _last_action.get(cid, 0) < MIN_GAP:
        abort(429)
    _last_action[cid] = now


def state(con):
    now = time.time()
    online = con.execute(
        "SELECT COUNT(*) FROM seen WHERE at > ?", (now - ONLINE_WINDOW,)
    ).fetchone()[0]
    votes = {c: 0 for c in ALLOWED_COLOURS}
    for r in con.execute("SELECT choice, COUNT(*) n FROM votes GROUP BY choice"):
        votes[r["choice"]] = r["n"]
    reactions = {k: 0 for k in REACTIONS}
    for r in con.execute("SELECT kind, n FROM reactions"):
        reactions[r["kind"]] = r["n"]
    return {
        "version": VERSION,
        "pod": POD,
        "colour": BUTTON_COLOUR,
        "online": online,
        "votes": votes,
        "reactions": reactions,
    }


@app.get("/")
def index():
    return render_template("index.html", colours=ALLOWED_COLOURS, reactions=REACTIONS,
                           colour=BUTTON_COLOUR, version=VERSION, pod=POD)


@app.get("/screen")
def screen():
    return render_template("screen.html", colour=BUTTON_COLOUR, version=VERSION)


@app.get("/reading")
def reading():
    return render_template("reading.html")


@app.get("/api/status")
def status():
    cid = client_id()  # polling doubles as the heartbeat
    with db() as con:
        con.execute("INSERT OR REPLACE INTO seen VALUES (?, ?)", (cid, time.time()))
        return jsonify(state(con))


@app.post("/api/vote")
def vote():
    cid = client_id()
    throttle(cid)
    choice = (request.get_json(silent=True) or {}).get("choice")
    if choice not in ALLOWED_COLOURS:
        abort(400)
    with db() as con:
        con.execute("INSERT OR REPLACE INTO votes VALUES (?, ?)", (cid, choice))
        return jsonify(state(con))


@app.post("/api/react")
def react():
    cid = client_id()
    throttle(cid)
    kind = (request.get_json(silent=True) or {}).get("kind")
    if kind not in REACTIONS:
        abort(400)
    with db() as con:
        con.execute(
            "INSERT INTO reactions VALUES (?, 1) ON CONFLICT(kind) DO UPDATE SET n = n + 1",
            (kind,),
        )
        return jsonify(state(con))


@app.post("/admin/reset")
def reset():
    token = os.environ.get("RESET_TOKEN")
    if not token or request.headers.get("X-Reset-Token") != token:
        abort(403)
    with db() as con:
        con.executescript("DELETE FROM seen; DELETE FROM votes; DELETE FROM reactions;")
    return jsonify(ok=True)


@app.get("/healthz")
def healthz():
    with db() as con:
        con.execute("SELECT 1")
    return "ok"
