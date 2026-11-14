"""Experimental LAN/VPN scenery replication. No Steam transport or TLS.

The browser controller is localhost-only. Only fixed scenery operations enter the
PID-bound game inbox; this service never evaluates commands or game scripts.
Network tests use an explicitly fake bridge and do not prove game multiplayer.
"""
from __future__ import annotations

import argparse
import ctypes
import hmac
import http.server
import json
import math
import os
from pathlib import Path
import queue
import re
import secrets
import socket
import struct
import threading
import time
import webbrowser

MAX_FRAME = 8192
MAX_PEERS = 8
DEFAULT_PORT = 28762
PROTOCOL = 1


class ProtocolError(ValueError):
    pass


def bounded_text(value, limit=40):
    return (isinstance(value, str) and 0 < len(value) <= limit
            and all(ord(c) >= 32 and ord(c) != 127 for c in value))


def coordinates(value):
    if (not isinstance(value, list) or len(value) != 3
            or any(type(n) not in (int, float) or not math.isfinite(n)
                   or abs(n) > 10000 for n in value)):
        raise ProtocolError("Koordinaten müssen drei endliche Zahlen zwischen -10000 und 10000 sein.")
    return [float(n) for n in value]


class Wire:
    def __init__(self, sock):
        self.sock = sock
        # Bound sendall even when a peer stops reading; leave receive idle-safe.
        timeout = 5000 if os.name == "nt" else struct.pack("ll", 5, 0)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDTIMEO, timeout)
        self.buffer = bytearray()
        self.lock = threading.Lock()

    def send(self, data):
        raw = json.dumps(data, ensure_ascii=True, allow_nan=False,
                         separators=(",", ":")).encode("ascii") + b"\n"
        if len(raw) > MAX_FRAME:
            raise ProtocolError("Nachricht zu groß.")
        with self.lock:
            self.sock.sendall(raw)

    def receive(self):
        while b"\n" not in self.buffer:
            if len(self.buffer) >= MAX_FRAME:
                raise ProtocolError("Nachricht zu groß.")
            chunk = self.sock.recv(min(4096, MAX_FRAME - len(self.buffer)))
            if not chunk:
                raise EOFError("Verbindung geschlossen.")
            self.buffer.extend(chunk)
        end = self.buffer.index(10)
        if end + 1 > MAX_FRAME:
            raise ProtocolError("Nachricht zu groß.")
        raw = bytes(self.buffer[:end])
        del self.buffer[:end + 1]
        try:
            result = json.loads(raw.decode("utf-8"),
                                parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
        except (ValueError, UnicodeError, RecursionError) as exc:
            raise ProtocolError("Ungültiges JSON.") from exc
        if not isinstance(result, dict):
            raise ProtocolError("JSON-Objekt erwartet.")
        return result

    def close(self):
        try:
            self.sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self.sock.close()


class RoomHost:
    """Single authoritative ordering point; each event needs every game ACK."""
    def __init__(self, port=DEFAULT_PORT, bind="0.0.0.0", key=None):
        self.key = key or secrets.token_urlsafe(24)
        self.lock = threading.RLock()
        self.peers = {}
        self.objects = {}
        self.dedupe = {}
        self.sequence = 0
        self.counter = 0
        self.ack_deadline = None
        self.failure = ""
        self.closed = False
        self.connections = threading.BoundedSemaphore(16)
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind((bind, port))
        self.port = self.sock.getsockname()[1]
        self.sock.listen(MAX_PEERS)
        self.sock.settimeout(0.5)
        threading.Thread(target=self._accept, daemon=True).start()

    def _accept(self):
        while not self.closed:
            try:
                sock, _ = self.sock.accept()
            except socket.timeout:
                with self.lock:
                    if (self.ack_deadline is not None and not self.failure
                            and time.monotonic() > self.ack_deadline
                            and any(p["applied"] != self.sequence for p in self.peers.values())):
                        self._fail("Spielbestätigung fehlt nach 65 Sekunden. Sitzung angehalten.")
                continue
            except OSError:
                break
            if not self.connections.acquire(blocking=False):
                sock.close()
                continue
            threading.Thread(target=self._serve, args=(sock,), daemon=True).start()

    def _peer_list(self):
        return [{"id": pid, "name": p["name"], "ready": p["ready"],
                 "applied": p["applied"]} for pid, p in self.peers.items()]

    def _broadcast(self, frame):
        for peer in list(self.peers.values()):
            try:
                peer["wire"].send(frame)
            except OSError:
                peer["wire"].close()

    def _fail(self, reason):
        if not self.failure:
            self.failure = str(reason)[:250]
            self._broadcast({"type": "fatal", "error": self.failure})

    def _serve(self, sock):
        wire = Wire(sock)
        pid = None
        try:
            sock.settimeout(8)
            hello = wire.receive()
            if (hello.get("type") != "hello" or hello.get("protocol") != PROTOCOL
                    or not bounded_text(hello.get("name"), 32)
                    or not isinstance(hello.get("key"), str)
                    or len(hello["key"]) > 128
                    or not hello["key"].isascii()
                    or not hmac.compare_digest(hello["key"], self.key)):
                raise ProtocolError("Raumschlüssel, Name oder Protokoll ungültig.")
            with self.lock:
                if self.sequence or self.failure:
                    raise ProtocolError("Bauen hat begonnen. Alle starten einen neuen leeren Raum/Testpark.")
                if len(self.peers) >= MAX_PEERS:
                    raise ProtocolError("Raum voll (maximal 8).")
                self.counter += 1
                pid = "p" + str(self.counter)
                self.peers[pid] = {"wire": wire, "name": hello["name"],
                                   "ready": False, "applied": 0, "counter": 0}
                wire.send({"type": "welcome", "peer": pid, "sequence": 0})
                self._broadcast({"type": "peers", "peers": self._peer_list()})
            sock.settimeout(None)
            while not self.closed:
                frame = wire.receive()
                with self.lock:
                    try:
                        self._handle(pid, frame)
                    except ProtocolError as exc:
                        wire.send({"type": "error", "error": str(exc)[:250]})
        except (OSError, EOFError, ProtocolError) as exc:
            try:
                wire.send({"type": "error", "error": str(exc)[:250]})
            except (OSError, ProtocolError):
                pass
        finally:
            with self.lock:
                if pid in self.peers:
                    self.peers.pop(pid)
                    if self.sequence and not self.closed:
                        self._fail("Spieler getrennt; Sitzung angehalten. Alle müssen neu starten.")
                    self._broadcast({"type": "peers", "peers": self._peer_list()})
            wire.close()
            self.connections.release()

    def _handle(self, pid, frame):
        peer = self.peers[pid]
        kind = frame.get("type")
        if kind == "ready":
            if type(frame.get("ready")) is not bool:
                raise ProtocolError("Bereitschaft ungültig.")
            if self.sequence and not frame["ready"]:
                self._fail("Ein Testpark ist nicht mehr bereit. Sitzung angehalten.")
            peer["ready"] = frame["ready"]
            self._broadcast({"type": "peers", "peers": self._peer_list()})
            return
        if kind == "ack":
            seq = frame.get("sequence")
            if type(seq) is not int or seq != self.sequence or seq != peer["applied"] + 1:
                raise ProtocolError("ACK-Reihenfolge ungültig.")
            if frame.get("ok") is not True:
                self._fail("Spiel meldet einen Fehler: " + str(frame.get("error", "unbekannt"))[:160])
            else:
                peer["applied"] = seq
            self._broadcast({"type": "peers", "peers": self._peer_list()})
            return
        if kind != "command":
            raise ProtocolError("Nachrichtentyp unbekannt.")
        if self.failure:
            raise ProtocolError(self.failure)
        op_id = frame.get("id")
        if not isinstance(op_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", op_id):
            raise ProtocolError("Operations-ID ungültig.")
        duplicate = self.dedupe.get((pid, op_id))
        if duplicate is not None:
            if duplicate[0] != frame:
                raise ProtocolError("Operations-ID wurde mit anderen Daten wiederverwendet.")
            peer["wire"].send({"type": "receipt", "sequence": duplicate[1], "duplicate": True})
            return
        if len(self.dedupe) >= 4096:
            raise ProtocolError("Alpha-Sitzungslimit erreicht. Neuen Raum starten.")
        if not self.peers or not all(p["ready"] for p in self.peers.values()):
            raise ProtocolError("Alle Spieler müssen zuerst ihren Testpark starten.")
        if any(p["applied"] != self.sequence for p in self.peers.values()):
            raise ProtocolError("Vorige Aktion wird noch in den Spielen bestätigt.")
        operation = frame.get("operation")
        oid = frame.get("object", "")
        if operation not in ("create", "move", "delete"):
            raise ProtocolError("Nur create, move und delete sind möglich.")
        if operation == "create":
            if len(self.objects) >= 1024:
                raise ProtocolError("Alpha-Objektlimit erreicht (1024).")
            pos = coordinates(frame.get("position"))
            peer["counter"] += 1
            oid = f"{pid}:{peer['counter']}"
            state = {"id": oid, "owner": pid, "name": peer["name"],
                     "resource": "AQ_Rock_04", "position": pos, "deleted": False}
        else:
            if not isinstance(oid, str) or not re.fullmatch(r"p[0-9]+:[0-9]+", oid):
                raise ProtocolError("Objekt-ID ungültig.")
            previous = self.objects.get(oid)
            if previous is None or previous["deleted"] or previous["owner"] != pid:
                raise ProtocolError("Du kannst nur deine eigenen vorhandenen Objekte ändern.")
            state = dict(previous)
            if operation == "move":
                state["position"] = coordinates(frame.get("position"))
            else:
                state["deleted"] = True
        self.sequence += 1
        self.ack_deadline = time.monotonic() + 65
        self.objects[oid] = state
        event = {"type": "event", "sequence": self.sequence, "operation": operation,
                 "object": dict(state), "peer": pid, "id": op_id}
        self.dedupe[(pid, op_id)] = (dict(frame), self.sequence)
        self._broadcast(event)

    def close(self):
        self.closed = True
        self.sock.close()
        with self.lock:
            for peer in list(self.peers.values()):
                peer["wire"].close()


def _alive(pid, game_dir):
    if os.name != "nt":
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.OpenProcess.restype = ctypes.c_void_p
    kernel.OpenProcess.argtypes = [ctypes.c_uint32, ctypes.c_int, ctypes.c_uint32]
    kernel.QueryFullProcessImageNameW.argtypes = [ctypes.c_void_p, ctypes.c_uint32,
                                                ctypes.c_wchar_p, ctypes.POINTER(ctypes.c_uint32)]
    kernel.CloseHandle.argtypes = [ctypes.c_void_p]
    handle = kernel.OpenProcess(0x1000, False, pid)
    if not handle:
        return False
    try:
        buf = ctypes.create_unicode_buffer(32768)
        size = ctypes.c_uint32(len(buf))
        if not kernel.QueryFullProcessImageNameW(handle, 0, buf, ctypes.byref(size)):
            return False
        actual = Path(buf.value).resolve()
        allowed = {game_dir.resolve(), (game_dir / "Win64").resolve()}
        return actual.parent in allowed and actual.name.lower() == "planetcoaster2.exe"
    finally:
        kernel.CloseHandle(handle)


class GameBridge:
    """One PID, one in-flight command, explicit testpark start, fixed grammar."""
    def __init__(self, game_dir):
        self.game_dir = Path(game_dir)
        self.mod_dir = self.game_dir / "Win64" / "ovldata" / "PC2CoopProbe"
        self.lock = threading.RLock()
        self.ready = False
        self.failure = ""
        self.pid = None
        self.log = None
        self.offset = 0
        self.partial = ""
        self.pending = None
        self.items = queue.Queue(maxsize=128)
        self.closed = False
        self.start_requested = False
        self.on_ack = lambda seq, ok, error: None
        self.on_ready = lambda ready: None
        threading.Thread(target=self._run, daemon=True).start()

    def _set_ready(self, value):
        if self.ready != value:
            self.ready = value
            self.on_ready(value)

    def _discover(self):
        candidates = sorted(self.mod_dir.glob("pc2coop-diagnostic-*.log"),
                            key=lambda p: p.stat().st_mtime, reverse=True)
        for path in candidates[:32]:
            match = re.fullmatch(r"pc2coop-diagnostic-([0-9]+)\.log", path.name)
            pid = int(match[1])
            if _alive(pid, self.game_dir):
                if self.pid is not None and self.pid != pid:
                    raise ProtocolError("Spielprozess hat gewechselt. Controller neu starten.")
                self.pid, self.log = pid, path
                return

    def _write(self, body):
        if self.pid is None:
            raise ProtocolError("PC2-Testkopie mit Mod zuerst starten.")
        target = self.mod_dir / f"pc2coop-inbox-{self.pid}.txt"
        temp = target.with_suffix(".tmp")
        temp.write_text(f"{time.time_ns()}|{body}", encoding="ascii")
        temp.replace(target)

    def start_park(self):
        with self.lock:
            if self.failure:
                raise ProtocolError(self.failure)
            if self.pending or self.ready or self.start_requested:
                raise ProtocolError("Testpark wurde bereits gestartet oder eine Aktion läuft.")
            self._discover()
            if self.log:
                self.offset = self.log.stat().st_size
                self.partial = ""
            self._write("new-test-park")
            self.start_requested = True
            self.start_deadline = time.monotonic() + 180

    def enqueue(self, event):
        with self.lock:
            if self.failure or not self.ready:
                self.on_ack(event["sequence"], False, self.failure or "Testpark nicht bereit.")
                return
            try:
                self.items.put_nowait(event)
            except queue.Full:
                self._fail("Lokale Befehlswarteschlange voll.")

    def _fail(self, error):
        if self.failure:
            return
        self.failure = str(error)[:250]
        if self.pending:
            seq = self.pending[0]["sequence"]
            self.pending = None
            self.on_ack(seq, False, self.failure)
        self._set_ready(False)

    def _line(self, line):
        line = line.rstrip("\r")
        if "live:ready" in line:
            if not self.start_requested:
                # Controller must explicitly start this park in this session.
                return
            self._set_ready(True)
        if ("live:stopped" in line or "live:not-ready" in line) and self.start_requested:
            self._fail("Testpark verlassen. Controller und Spiel neu starten.")
        if ("live:protocol-error" in line or "live:tick-error" in line) and self.start_requested:
            self._fail(line[-200:])
        match = re.search(r"\blive:ack:([0-9]+):(ok|error)(?::(.*))?", line)
        if match and self.pending:
            seq = int(match[1])
            if seq != self.pending[0]["sequence"]:
                self._fail("Spiel-ACK hat falsche Reihenfolge.")
                return
            self.pending = None
            ok = match[2] == "ok"
            error = (match[3] or "Spielaktion fehlgeschlagen.")[:200]
            self.on_ack(seq, ok, "" if ok else error)
            if not ok:
                self._fail(error)

    def _run(self):
        while not self.closed:
            try:
                with self.lock:
                    if self.failure:
                        pass
                    else:
                        if self.log is None:
                            self._discover()
                        if self.log:
                            if not _alive(self.pid, self.game_dir):
                                raise ProtocolError("PC2 wurde geschlossen. Sitzung angehalten.")
                            with self.log.open("rb") as stream:
                                stream.seek(self.offset)
                                raw = stream.read(256 * 1024)
                                self.offset += len(raw)
                            self.partial += raw.decode("utf-8", errors="replace")
                            lines = self.partial.split("\n")
                            self.partial = lines.pop()[-8192:]
                            for line in lines:
                                self._line(line)
                        if self.start_requested and not self.ready and time.monotonic() > self.start_deadline:
                            self._fail("Testpark nach 180 Sekunden nicht bereit.")
                        if self.pending and time.monotonic() > self.pending[1]:
                            self._fail("Spielaktion nach 60 Sekunden nicht bestätigt.")
                        if self.ready and not self.pending and not self.items.empty():
                            event = self.items.get_nowait()
                            pos = coordinates(event["object"]["position"])
                            body = "live|{}|{}|{}|{}|{}|{}".format(
                                event["sequence"], event["operation"], event["object"]["id"],
                                *[format(n, ".9g") for n in pos])
                            self._write(body)
                            self.pending = (event, time.monotonic() + 60)
            except (OSError, ValueError, KeyError) as exc:
                with self.lock:
                    self._fail(str(exc))
            time.sleep(0.2)

    def close(self):
        self.closed = True

    def abort(self, error):
        with self.lock:
            self._fail(error)


class RoomClient:
    def __init__(self, address, port, key, name, bridge):
        if not bounded_text(name, 32) or not bounded_text(address, 200):
            raise ProtocolError("Name oder Adresse ungültig.")
        if not isinstance(key, str) or not 1 <= len(key) <= 128:
            raise ProtocolError("Raumschlüssel fehlt.")
        self.bridge = bridge
        self.lock = threading.RLock()
        self.peer = None
        self.peers = []
        self.objects = {}
        self.sequence = 0
        self.error = ""
        self.fatal = False
        self.connected = False
        self.closed = False
        sock = socket.create_connection((address, port), timeout=8)
        self.wire = Wire(sock)
        try:
            self.wire.send({"type": "hello", "protocol": PROTOCOL, "key": key, "name": name})
            welcome = self.wire.receive()
            if welcome.get("type") != "welcome":
                raise ProtocolError(welcome.get("error", "Verbindung abgewiesen."))
            self.peer = welcome["peer"]
            self.connected = True
            sock.settimeout(None)
            bridge.on_ack = self._ack
            bridge.on_ready = self._ready
            self._ready(bridge.ready)
            threading.Thread(target=self._run, daemon=True).start()
        except Exception:
            self.wire.close()
            raise

    def _ready(self, value):
        try:
            self.wire.send({"type": "ready", "ready": value})
        except OSError:
            self.connected = False

    def _ack(self, seq, ok, error):
        try:
            self.wire.send({"type": "ack", "sequence": seq, "ok": ok, "error": str(error)[:200]})
        except OSError:
            self.connected = False

    def _run(self):
        try:
            while not self.closed:
                frame = self.wire.receive()
                with self.lock:
                    kind = frame.get("type")
                    if kind == "event":
                        if (type(frame.get("sequence")) is not int
                                or frame["sequence"] != self.sequence + 1):
                            raise ProtocolError("Netzwerk-Reihenfolge ungültig.")
                        obj = frame.get("object")
                        if (frame.get("operation") not in ("create", "move", "delete")
                                or not isinstance(obj, dict)
                                or not isinstance(obj.get("id"), str)
                                or not re.fullmatch(r"p[0-9]{1,8}:[0-9]{1,8}", obj["id"])
                                or obj.get("resource") != "AQ_Rock_04"
                                or not bounded_text(obj.get("name"), 32)
                                or not isinstance(obj.get("owner"), str)
                                or not re.fullmatch(r"p[0-9]{1,8}", obj["owner"])
                                or type(obj.get("deleted")) is not bool):
                            raise ProtocolError("Ungültiges Objekt vom Host.")
                        coordinates(obj.get("position"))
                        self.sequence = frame["sequence"]
                        self.objects[frame["object"]["id"]] = frame["object"]
                        self.bridge.enqueue(frame)
                    elif kind == "peers":
                        self.peers = frame["peers"]
                    elif kind in ("error", "fatal"):
                        self.error = str(frame.get("error", "Unbekannter Fehler"))[:250]
                        if kind == "fatal":
                            self.fatal = True
                            self.bridge.abort(self.error)
        except (OSError, EOFError, ProtocolError, KeyError, TypeError) as exc:
            if not self.closed:
                self.error = str(exc)[:250]
                self.fatal = True
        finally:
            self.connected = False

    def command(self, operation, position=None, object_id="", operation_id=None):
        if not self.connected or self.fatal:
            raise ProtocolError(self.error or "Kein aktiver Raum.")
        frame = {"type": "command", "id": operation_id or secrets.token_hex(12),
                 "operation": operation, "object": object_id}
        if operation != "delete":
            frame["position"] = coordinates(position)
        self.wire.send(frame)

    def close(self):
        self.closed = True
        self.connected = False
        self.wire.close()


HTML = r'''<!doctype html><html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>PC2 Coop – experimentelle LAN-Alpha</title><style>
body{font:16px system-ui;background:#17212b;color:#e8eff4;max-width:900px;margin:35px auto;padding:0 20px}input,button,select{font:inherit;padding:9px;margin:4px;border-radius:5px}button{cursor:pointer;background:#90e0c4;border:0}input{max-width:230px}fieldset{margin:20px 0;border:1px solid #657687;border-radius:8px}#error{color:#ffc6bf;white-space:pre-wrap}table{border-collapse:collapse;width:100%}td,th{padding:10px;text-align:left;border-bottom:1px solid #425364}small{color:#bed0de}#key{overflow-wrap:anywhere}</style>
<h1>PC2 Coop – LAN-Alpha</h1><p>Experimenteller Test: gemeinsame Felsen über dieses Fenster platzieren, verschieben und löschen. Normales Bauen und Kameras sind noch nicht synchronisiert. Jeder braucht die gleiche Spielversion und einen frischen Testpark.</p>
<p><strong>Nur im vertrauenswürdigen LAN oder in eurem vorhandenen VPN nutzen.</strong> Verbindung ohne TLS. Keine Ports ins Internet freigeben. Erst alle verbinden und Testparks starten, dann bauen. Nach dem ersten Bau ist Beitreten gesperrt.</p>
<fieldset><legend>1 · Raum</legend><label>Name <input id="name" maxlength="32" value="Spieler"></label><br><button id="host">Raum hosten</button><small id="port"></small><p id="key"></p><hr>
<input id="address" placeholder="Host-IP / VPN-IP" maxlength="200"><input id="room" placeholder="Raumschlüssel" maxlength="128"><button id="join">Beitreten</button></fieldset>
<fieldset><legend>2 · Spiel</legend><p>Starte zuerst die installierte PC2-Testkopie bis ins Hauptmenü. Dieser Knopf lädt ausschließlich einen neuen Park namens PC2Coop-Test. Ein vorhandener Park wird dabei verlassen.</p><button id="start">Testpark starten</button><p id="status">Lade Status …</p><div id="peers"></div></fieldset>
<fieldset><legend>3 · Gemeinsam testen</legend><p>Koordinaten in Metern. Jeder kann seine eigenen Objekte ändern. Warte nach jeder Aktion auf alle Spielbestätigungen.</p>
<label>X <input id="x" type="number" value="10" min="-10000" max="10000" step="0.1"></label><label>Y <input id="y" type="number" value="5" min="-10000" max="10000" step="0.1"></label><label>Z <input id="z" type="number" value="10" min="-10000" max="10000" step="0.1"></label><br><button id="create">AQ_Rock_04 platzieren</button>
<table><thead><tr><th>Objekt</th><th>Erbauer</th><th>Position</th><th>Aktionen</th></tr></thead><tbody id="objects"></tbody></table></fieldset><p id="error"></p><small>Bei einem Spiel- oder Verbindungsfehler stoppt die Sitzung. Alle Controller und Testparks gemeinsam neu starten. Kein Speichern/Laden, kein späterer Beitritt.</small>
<script>
const token='__TOKEN__';let state={};const $=id=>document.getElementById(id);
async function post(action,data={}){try{const r=await fetch('/api/'+action,{method:'POST',headers:{'Content-Type':'application/json','X-PC2-Token':token},body:JSON.stringify(data)});const v=await r.json();if(!r.ok)throw Error(v.error);$('error').textContent='';await refresh()}catch(e){$('error').textContent=e.message}}
function pos(){return ['x','y','z'].map(id=>Number($(id).value))}
$('host').onclick=()=>post('host',{name:$('name').value});$('join').onclick=()=>post('join',{name:$('name').value,address:$('address').value,key:$('room').value});$('start').onclick=()=>post('start');$('create').onclick=()=>post('command',{operation:'create',position:pos()});
async function refresh(){try{const r=await fetch('/api/state');state=await r.json();$('port').textContent=' TCP-Port '+state.port;$('key').textContent=state.key?'Raumschlüssel (nur Freunden geben): '+state.key:'';$('host').disabled=$('join').disabled=state.connected;$('start').disabled=state.game_ready||state.start_requested||!state.connected;$('status').textContent='Spielprozess: '+(state.pid||'nicht gefunden')+' · Park: '+(state.game_ready?'bereit':'nicht bereit')+' · Raum: '+(state.connected?'verbunden als '+state.peer:'getrennt')+' · Aktion '+state.sequence;$('peers').textContent=(state.peers||[]).map(p=>p.name+': '+(p.ready?'bereit':'wartet')+' · bestätigt '+p.applied).join(' | ');const allReady=state.connected&&!state.fatal&&state.peers.length&&state.peers.every(p=>p.ready&&p.applied===state.sequence);$('create').disabled=!allReady;const body=$('objects');body.replaceChildren();Object.values(state.objects||{}).filter(o=>!o.deleted).forEach(o=>{const tr=document.createElement('tr');[o.id,o.name,o.position.join(', ')].forEach(v=>{const td=document.createElement('td');td.textContent=v;tr.append(td)});const td=document.createElement('td');['move','delete'].forEach(op=>{const b=document.createElement('button');b.textContent=op==='move'?'Hierhin verschieben':'Löschen';b.disabled=o.owner!==state.peer||!allReady;b.onclick=()=>post('command',{operation:op,object:o.id,position:pos()});td.append(b)});tr.append(td);body.append(tr)});if(state.error)$('error').textContent=state.error}catch(e){$('status').textContent='Controller nicht erreichbar.'}}
refresh();setInterval(refresh,1000);
</script></html>'''


class Controller:
    def __init__(self, game_dir, port=DEFAULT_PORT, bridge=None):
        self.bridge = bridge or GameBridge(game_dir)
        self.port = port
        self.host = None
        self.client = None
        self.lock = threading.RLock()
        self.token = secrets.token_hex(24)

    def action(self, action, data):
        with self.lock:
            if action in ("host", "join"):
                if self.client:
                    raise ProtocolError("Controller für einen neuen Raum neu starten.")
                if action == "host":
                    self.host = RoomHost(self.port)
                    try:
                        self.client = RoomClient("127.0.0.1", self.host.port,
                                                 self.host.key, data.get("name"), self.bridge)
                    except Exception:
                        self.host.close()
                        self.host = None
                        raise
                else:
                    self.client = RoomClient(data.get("address"), self.port,
                                             data.get("key"), data.get("name"), self.bridge)
            elif action == "start":
                if not self.client or not self.client.connected:
                    raise ProtocolError("Zuerst Raum hosten oder beitreten.")
                self.bridge.start_park()
            elif action == "command":
                if not self.client:
                    raise ProtocolError("Zuerst verbinden.")
                self.client.command(data.get("operation"), data.get("position"), data.get("object", ""))
            else:
                raise ProtocolError("Aktion unbekannt.")

    def state(self):
        with self.lock:
            c = self.client
            return {"port": self.host.port if self.host else self.port,
                    "key": self.host.key if self.host else "", "pid": self.bridge.pid,
                    "game_ready": self.bridge.ready, "start_requested": self.bridge.start_requested,
                    "connected": bool(c and c.connected), "peer": c.peer if c else None,
                    "peers": list(c.peers) if c else [], "objects": dict(c.objects) if c else {},
                    "sequence": c.sequence if c else 0, "fatal": bool(c and c.fatal),
                    "error": self.bridge.failure or (c.error if c else "")}

    def close(self):
        if self.client:
            self.client.close()
        if self.host:
            self.host.close()
        self.bridge.close()


def serve(controller, html=None):
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def reply(self, value, code=200, html=False):
            raw = value.encode("utf-8") if html else json.dumps(value, allow_nan=False).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "text/html; charset=utf-8" if html else "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'")
            self.end_headers()
            self.wfile.write(raw)

        def valid_host(self):
            return self.headers.get("Host") == f"127.0.0.1:{self.server.server_port}"

        def do_GET(self):
            if not self.valid_host():
                self.reply({"error": "Host ungültig."}, 403)
            elif self.path == "/":
                self.reply((html or HTML).replace("__TOKEN__", controller.token), html=True)
            elif self.path == "/api/state":
                self.reply(controller.state())
            else:
                self.reply({"error": "Nicht gefunden."}, 404)

        def do_POST(self):
            supplied_token = self.headers.get("X-PC2-Token", "")
            if (not self.valid_host() or not supplied_token.isascii()
                    or not hmac.compare_digest(supplied_token, controller.token)):
                self.reply({"error": "Lokaler Zugriffsschlüssel fehlt."}, 403)
                return
            try:
                size = int(self.headers.get("Content-Length", "0"))
                if not 1 <= size <= MAX_FRAME:
                    raise ProtocolError("Anfrage zu groß oder leer.")
                data = json.loads(self.rfile.read(size))
                if not isinstance(data, dict) or not self.path.startswith("/api/"):
                    raise ProtocolError("Anfrage ungültig.")
                controller.action(self.path[5:], data)
                self.reply({"ok": True})
            except (ValueError, OSError, TypeError, RecursionError) as exc:
                self.reply({"error": str(exc)[:250]}, 400)

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    return server


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-dir", required=True, type=Path)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--no-browser", action="store_true")
    args = parser.parse_args(argv)
    if not 1 <= args.port <= 65535:
        parser.error("Port muss zwischen 1 und 65535 liegen.")
    if not (args.game_dir / "Win64" / "ovldata" / "PC2CoopProbe").is_dir():
        parser.error("PC2CoopProbe fehlt in dieser Spielkopie.")
    controller = Controller(args.game_dir, args.port)
    server = serve(controller)
    url = f"http://127.0.0.1:{server.server_port}/"
    print("Experimentelle PC2-LAN-Alpha. Controller:", url, flush=True)
    print("Nur LAN / vorhandenes VPN. Ohne TLS. Strg+C beendet den Controller.", flush=True)
    if not args.no_browser:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        controller.close()


if __name__ == "__main__":
    main()
