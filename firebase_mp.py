"""Firebase Realtime Database client for online races and chat.

Uses the public REST API plus anonymous Auth so the game can run on
desktop and Android without the Admin SDK. Incoming room data is read
from the REST event stream; poses, shots, and chat are written on a
separate keep-alive connection. Configure with `firebase_config.json`
(see firebase_config.example.json) or:

    FIREBASE_API_KEY
    FIREBASE_DB_URL
"""
from __future__ import annotations

import http.client
import io
import json
import os
import random
import ssl
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request


POSE_INTERVAL = 0.045
POLL_INTERVAL = 0.05
STREAM_TIMEOUT = 75.0
WRITE_TIMEOUT = 4.0


def _config_candidates():
    names = ("firebase_config.json", "firebase_config.example.json")
    bases = []
    if getattr(sys, "_MEIPASS", None):
        bases.append(sys._MEIPASS)
    here = os.path.dirname(os.path.abspath(__file__))
    bases.extend((os.getcwd(), here))
    for base in bases:
        for name in names:
            path = os.path.join(base, name)
            if os.path.isfile(path):
                yield path


def load_firebase_config():
    api = os.environ.get("FIREBASE_API_KEY", "").strip()
    url = os.environ.get("FIREBASE_DB_URL", "").strip()
    for path in _config_candidates():
        try:
            with open(path, encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, json.JSONDecodeError):
            continue
        api = api or str(data.get("apiKey") or data.get("api_key") or "").strip()
        url = url or str(data.get("databaseURL") or data.get("database_url") or "").strip()
        if api and url and "YOUR_" not in api and "YOUR_" not in url:
            break
        # Keep looking if this was only the example placeholder.
    url = url.rstrip("/")
    if url and not url.startswith("http"):
        url = "https://" + url
    ok = bool(api and url and "YOUR_" not in api and "YOUR_" not in url)
    return {"apiKey": api, "databaseURL": url, "ok": ok}


def new_room_code():
    return str(random.randint(10000, 99999))


_AUTH_OPTIONAL = (
    "CONFIGURATION_NOT_FOUND",
    "OPERATION_NOT_ALLOWED",
    "ADMIN_ONLY_OPERATION",
    "API_NOT_ACTIVATED",
)


def _http_error_text(exc):
    raw = ""
    if isinstance(exc, urllib.error.HTTPError):
        try:
            raw = exc.read().decode("utf-8", "replace")
        except Exception:
            raw = ""
        try:
            data = json.loads(raw) if raw else {}
            err = data.get("error")
            if isinstance(err, dict):
                return str(err.get("message") or err.get("status") or raw or exc)
            if err:
                return str(err)
        except json.JSONDecodeError:
            pass
        return (raw or str(exc)).strip()[:240]
    return str(exc)


def _friendly_error(exc):
    msg = _http_error_text(exc)
    upper = msg.upper()
    if "PERMISSION_DENIED" in upper or "PERMISSION DENIED" in upper:
        return "Database rules blocked the room. Publish firebase_rules.json on Realtime Database."
    if "CONFIGURATION_NOT_FOUND" in upper:
        return "Firebase Authentication is not enabled for this project."
    if "OPERATION_NOT_ALLOWED" in upper:
        return "Enable Anonymous sign-in in Firebase Authentication."
    return msg[:200]


def _deep_update(dst, src):
    for key, value in src.items():
        if value is None:
            dst.pop(key, None)
        elif isinstance(value, dict) and isinstance(dst.get(key), dict):
            _deep_update(dst[key], value)
        else:
            dst[key] = value


class _HttpsPool:
    """Reuse one TLS connection so pose writes skip a handshake each tick."""

    def __init__(self, host):
        self.host = host
        self._conn = None
        self._lock = threading.Lock()
        self._ssl = ssl.create_default_context()

    def close(self):
        with self._lock:
            self._close_unlocked()

    def _close_unlocked(self):
        if self._conn is not None:
            try:
                self._conn.close()
            except Exception:
                pass
            self._conn = None

    def request(self, method, path, body=None, headers=None, timeout=WRITE_TIMEOUT):
        headers = dict(headers or {})
        headers.setdefault("Connection", "keep-alive")
        if body is not None:
            headers["Content-Type"] = "application/json"
            headers["Content-Length"] = str(len(body))
        last = None
        with self._lock:
            for _ in range(2):
                try:
                    if self._conn is None:
                        self._conn = http.client.HTTPSConnection(
                            self.host, timeout=timeout, context=self._ssl)
                    else:
                        self._conn.timeout = timeout
                        if self._conn.sock is not None:
                            self._conn.sock.settimeout(timeout)
                    self._conn.request(method, path, body=body, headers=headers)
                    resp = self._conn.getresponse()
                    data = resp.read()
                    if resp.status >= 400:
                        raise urllib.error.HTTPError(
                            f"https://{self.host}{path}", resp.status,
                            resp.reason, resp.headers, io.BytesIO(data))
                    return resp.status, data
                except urllib.error.HTTPError:
                    raise
                except Exception as exc:
                    last = exc
                    self._close_unlocked()
        raise last


class FirebaseSession:
    """Live room stream + low-latency writes for poses, shots, and chat."""

    def __init__(self):
        self.cfg = load_firebase_config()
        self.lock = threading.Lock()
        self.uid = ""
        self.token = ""
        self.refresh_token = ""
        self.room = ""
        self.host = False
        self.display_name = "RACER"
        self.error = ""
        self.status = "offline"
        self.players = {}
        self.chat = []
        self.shots = {}
        self.meta = {}
        self._room = {}
        self._running = False
        self._write_thread = None
        self._stream_thread = None
        self._player_payload = None
        self._chat_queue = []
        self._shot_queue = []
        self._dirty_player = False
        self._last_pose_send = 0.0
        self._last_sent_player = None
        self._write_event = threading.Event()
        self._streaming = False
        self._stream_conn = None
        host = urllib.parse.urlparse(self.cfg.get("databaseURL") or "").hostname or ""
        self._http = _HttpsPool(host) if host else None

    @property
    def configured(self):
        return bool(self.cfg.get("ok"))

    def connect(self):
        if self.uid:
            self._ensure_threads()
            return True
        if not self.configured:
            self.error = "missing firebase_config.json (apiKey + databaseURL)"
            self.status = "offline"
            return False
        try:
            self._sign_in()
        except Exception as exc:
            msg = _http_error_text(exc)
            if not any(tag in msg.upper() for tag in _AUTH_OPTIONAL):
                self.error = _friendly_error(exc)
                self.status = "error"
                return False
            self._guest_session()
        self.status = "connected"
        self.error = ""
        self._ensure_threads()
        return True

    def _guest_session(self):
        self.token = ""
        self.refresh_token = ""
        self.uid = "G" + format(random.getrandbits(48), "012x")
        self.display_name = "RACER-" + self.uid[-4:].upper()

    def create_room(self, meta):
        if not self.uid and not self.connect():
            return None
        try:
            for _ in range(8):
                code = new_room_code()
                existing = self._req("GET", f"rooms/{code}")
                if existing:
                    continue
                payload = {
                    "meta": dict(meta, host=self.uid, created=int(time.time()),
                                 started=False),
                    "players": {},
                    "chat": {},
                    "shots": {},
                }
                self._req("PUT", f"rooms/{code}", payload)
                self.room = code
                self.host = True
                self.status = "in-room"
                self.meta = payload["meta"]
                with self.lock:
                    self._room = payload
                    self._refresh_from_room()
                self._write_event.set()
                return code
            self.error = "could not allocate a room code"
            return None
        except Exception as exc:
            self.error = _friendly_error(exc)
            self.status = "error"
            return None

    def join_room(self, code):
        if not self.uid and not self.connect():
            return False
        code = "".join(ch for ch in str(code) if ch.isdigit())
        if len(code) != 5:
            self.error = "room code must be 5 digits"
            return False
        try:
            data = self._req("GET", f"rooms/{code}")
        except Exception as exc:
            self.error = _friendly_error(exc)
            self.status = "error"
            return False
        if not data:
            self.error = f"no room {code}"
            return False
        self.room = code
        self.host = False
        self.status = "in-room"
        self.error = ""
        self._ingest(data)
        self._write_event.set()
        return True

    def leave(self):
        uid, room = self.uid, self.room
        self.room = ""
        self.host = False
        self.players = {}
        self.chat = []
        self.shots = {}
        self.meta = {}
        self._player_payload = None
        self._shot_queue = []
        self._chat_queue = []
        self._dirty_player = False
        self._last_sent_player = None
        self._streaming = False
        conn = self._stream_conn
        self._stream_conn = None
        if conn is not None:
            try:
                conn.close()
            except Exception:
                pass
        with self.lock:
            self._room = {}
        self._write_event.set()
        if uid and room:
            try:
                self._req("DELETE", f"rooms/{room}/players/{uid}", silent=True)
            except Exception:
                pass
        self.status = "connected" if (self.token or self.uid) else "offline"

    def set_player(self, payload):
        with self.lock:
            self._player_payload = dict(payload)
            self._dirty_player = True
        self._write_event.set()

    def send_chat(self, text):
        text = " ".join(str(text).split())[:120]
        if not text or not self.room:
            return
        with self.lock:
            self._chat_queue.append({
                "uid": self.uid,
                "name": self.display_name,
                "text": text,
                "ts": int(time.time() * 1000),
            })
        self._write_event.set()

    def send_shot(self, payload):
        if not self.room:
            return
        with self.lock:
            self._shot_queue.append(dict(payload))
        self._write_event.set()

    def snapshot(self):
        with self.lock:
            return {
                "players": dict(self.players),
                "chat": list(self.chat),
                "shots": dict(self.shots),
                "meta": dict(self.meta),
                "error": self.error,
                "status": self.status,
                "room": self.room,
                "uid": self.uid,
                "host": self.host,
            }

    def mark_started(self, extra_meta=None):
        if not (self.host and self.room):
            return
        meta = dict(self.meta)
        meta["started"] = True
        if extra_meta:
            meta.update(extra_meta)
        self.meta = meta
        self._req("PUT", f"rooms/{self.room}/meta", meta, silent=True)

    def shutdown(self):
        self._running = False
        self._write_event.set()
        self.leave()
        if self._http:
            self._http.close()

    # ---------------------------------------------------------------- http
    def _sign_in(self):
        body = self._http_json(
            "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key="
            + urllib.parse.quote(self.cfg["apiKey"]),
            {"returnSecureToken": True})
        self.token = body.get("idToken") or ""
        self.uid = body.get("localId") or ""
        self.refresh_token = body.get("refreshToken") or ""
        if not self.token or not self.uid:
            raise RuntimeError("CONFIGURATION_NOT_FOUND")
        self.display_name = "RACER-" + self.uid[-4:].upper()

    def _url(self, path, silent=False):
        path = path.strip("/")
        url = f"{self.cfg['databaseURL']}/{path}.json"
        parsed = urllib.parse.urlparse(url)
        params = urllib.parse.parse_qsl(parsed.query, keep_blank_values=True)
        if self.token:
            params.append(("auth", self.token))
        if silent:
            params.append(("print", "silent"))
        query = urllib.parse.urlencode(params)
        return parsed.hostname, parsed.path + (("?" + query) if query else "")

    def _req(self, method, path, payload=None, silent=False):
        body = None if payload is None else json.dumps(payload, separators=(",", ":")).encode("utf-8")
        host, url_path = self._url(path, silent=silent)
        if self._http is None or self._http.host != host:
            self._http = _HttpsPool(host)
        try:
            _status, data = self._http.request(method, url_path, body=body)
        except urllib.error.HTTPError as exc:
            raise RuntimeError(_friendly_error(exc)) from exc
        if not data:
            return None
        raw = data.decode("utf-8") or "null"
        return json.loads(raw)

    def _http_json(self, url, payload):
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            url, data=data, method="POST",
            headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=8) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            raise RuntimeError(_http_error_text(exc)) from exc

    def _ensure_threads(self):
        self._running = True
        if not (self._write_thread and self._write_thread.is_alive()):
            self._write_thread = threading.Thread(
                target=self._write_loop, name="firebase-write", daemon=True)
            self._write_thread.start()
        if not (self._stream_thread and self._stream_thread.is_alive()):
            self._stream_thread = threading.Thread(
                target=self._stream_loop, name="firebase-stream", daemon=True)
            self._stream_thread.start()

    def _write_loop(self):
        while self._running:
            self._write_event.wait(POSE_INTERVAL)
            self._write_event.clear()
            try:
                self._flush_writes()
            except Exception as exc:
                with self.lock:
                    self.error = _friendly_error(exc)
                    self.status = "error"

    def _flush_writes(self):
        room = self.room
        if not room or not self.uid:
            return
        chats, shots, player = [], [], None
        now = time.time()
        with self.lock:
            if self._chat_queue:
                chats = self._chat_queue
                self._chat_queue = []
            if self._shot_queue:
                shots = self._shot_queue
                self._shot_queue = []
            if (self._dirty_player and self._player_payload
                    and now - self._last_pose_send >= POSE_INTERVAL):
                player = dict(self._player_payload)
                self._dirty_player = False
                self._last_pose_send = now
        for item in chats:
            self._req("POST", f"rooms/{room}/chat", item, silent=True)
        for item in shots:
            self._req("POST", f"rooms/{room}/shots", item, silent=True)
        if player and player != self._last_sent_player:
            self._req("PUT", f"rooms/{room}/players/{self.uid}", player, silent=True)
            self._last_sent_player = player

    def _stream_loop(self):
        while self._running:
            room = self.room
            if not room:
                self._streaming = False
                time.sleep(POLL_INTERVAL)
                continue
            try:
                streamed = self._consume_stream(room)
                if not streamed:
                    self._poll_room()
                    time.sleep(POLL_INTERVAL)
            except Exception as exc:
                self._streaming = False
                msg = _friendly_error(exc)
                if "blocked" in msg.lower() or "permission" in msg.lower():
                    with self.lock:
                        self.error = msg
                        if self.room:
                            self.status = "error"
                time.sleep(POLL_INTERVAL)

    def _poll_room(self):
        room = self.room
        if not room:
            return
        data = self._req("GET", f"rooms/{room}") or {}
        self._ingest(data)

    def _consume_stream(self, room):
        host, url_path = self._url(f"rooms/{room}")
        ctx = ssl.create_default_context()
        conn = http.client.HTTPSConnection(host, timeout=STREAM_TIMEOUT, context=ctx)
        try:
            conn.request("GET", url_path, headers={
                "Accept": "text/event-stream",
                "Cache-Control": "no-cache",
            })
            resp = conn.getresponse()
            ctype = (resp.getheader("Content-Type") or "").lower()
            if resp.status != 200:
                body = resp.read()
                raise urllib.error.HTTPError(
                    f"https://{host}{url_path}", resp.status, resp.reason,
                    resp.headers, io.BytesIO(body))
            if "text/event-stream" not in ctype:
                raw = resp.read().decode("utf-8") or "null"
                self._ingest(json.loads(raw))
                return False
            self._streaming = True
            self._stream_conn = conn
            event = "message"
            data_lines = []
            while self._running and self.room == room:
                line = resp.fp.readline()
                if not line:
                    break
                text = line.decode("utf-8", "replace").rstrip("\r\n")
                if text.startswith("event:"):
                    event = text[6:].strip()
                elif text.startswith("data:"):
                    data_lines.append(text[5:].lstrip())
                elif text == "":
                    if data_lines:
                        self._handle_sse(event, "\n".join(data_lines))
                    event = "message"
                    data_lines = []
            return True
        finally:
            self._streaming = False
            if self._stream_conn is conn:
                self._stream_conn = None
            try:
                conn.close()
            except Exception:
                pass

    def _handle_sse(self, event, raw):
        if event in ("keep-alive", "auth_revoked", "cancel"):
            return
        if event not in ("put", "patch", "message"):
            return
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            return
        if not isinstance(payload, dict):
            return
        path = str(payload.get("path") or "/")
        data = payload.get("data")
        self._apply_path(path, data, patch=(event == "patch"))

    def _apply_path(self, path, data, patch=False):
        parts = [p for p in path.strip("/").split("/") if p]
        with self.lock:
            if not parts:
                if data is None:
                    self._room = {}
                elif patch and isinstance(data, dict) and isinstance(self._room, dict):
                    _deep_update(self._room, data)
                else:
                    self._room = data if isinstance(data, dict) else {}
            else:
                if not isinstance(self._room, dict):
                    self._room = {}
                cur = self._room
                for part in parts[:-1]:
                    nxt = cur.get(part)
                    if not isinstance(nxt, dict):
                        nxt = {}
                        cur[part] = nxt
                    cur = nxt
                key = parts[-1]
                if data is None:
                    cur.pop(key, None)
                elif patch and isinstance(data, dict) and isinstance(cur.get(key), dict):
                    _deep_update(cur[key], data)
                else:
                    cur[key] = data
            self._refresh_from_room()

    def _ingest(self, data):
        with self.lock:
            self._room = data if isinstance(data, dict) else {}
            self._refresh_from_room()

    def _refresh_from_room(self):
        data = self._room if isinstance(self._room, dict) else {}
        players = data.get("players") or {}
        chat = data.get("chat") or {}
        shots = data.get("shots") or {}
        meta = data.get("meta") or {}
        messages = []
        if isinstance(chat, dict):
            for key, msg in chat.items():
                if not isinstance(msg, dict):
                    continue
                messages.append((msg.get("ts") or 0, key, msg))
            messages.sort()
        self.players = players if isinstance(players, dict) else {}
        self.shots = shots if isinstance(shots, dict) else {}
        self.meta = meta if isinstance(meta, dict) else {}
        self.chat = [m for _ts, _k, m in messages][-24:]
        if self.status == "error" and self.room:
            self.status = "in-room"
            self.error = ""
