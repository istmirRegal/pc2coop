"""PC2 live co-op: host authority, game link, network host/client and local controller.

Data flow per player:  PC2 (sync.lua) --log lines--> GameLink --TCP--> host Authority
host Authority --ordered op lines--> every client's GameLink --inbox file--> PC2.

The host is authoritative. Every synced object carries a revision; a change based on
an old revision is rejected and the author's game is restored to the host state, which
acts as an edit lock without ever blocking the game. No Steam transport, no TLS: use
LAN, a VPN (e.g. Tailscale/ZeroTier) or a forwarded port with a strong room key.
"""
from __future__ import annotations

import argparse
import hmac
import json
import math
import os
from pathlib import Path
import re
import secrets
import socket
import threading
import time
import webbrowser

from .alpha import MAX_FRAME, ProtocolError, Wire, _alive, bounded_text, serve as serve_http

PROTOCOL = 2
DEFAULT_PORT = 28763
MAX_PEERS = 8
INBOX_LIMIT = 3800
COLORS = ["#ff6b6b", "#4dabf7", "#51cf66", "#fcc419", "#cc5de8", "#ff922b", "#22b8cf", "#f06595"]
RESOURCE = re.compile(r"^[A-Za-z0-9_.\-]{1,96}$")
GID = re.compile(r"^[A-Za-z0-9_.\-]{1,64}$")


def finite(values, limit=1e6):
    if not all(type(v) in (int, float) and math.isfinite(v) and abs(v) <= limit for v in values):
        raise ProtocolError("Ungültige Zahl.")
    return [float(v) for v in values]


def num(v):
    return format(v, ".9g")


def clean_name(name):
    name = "".join(c for c in str(name) if c.isprintable() and c not in "|\n\r")[:32].strip()
    return name or "Spieler"


# --------------------------------------------------------------------------------------
# Authority: pure host logic, no sockets. Deliveries are (peer, line) pairs.

class Authority:
    def __init__(self, objects=None, stats=None):
        self.objects = objects or {}      # gid -> state dict
        self.tombstones = {}              # gid -> revision at deletion
        self.players = {}                 # peer -> {"name","color","pres","base"}
        self.stats = stats or {}          # name -> {"created","edited","deleted"}
        self.feed = []
        self.counter = 0
        self.conflicts = 0
        self.changed = False

    # -- players
    def join(self, peer, name):
        color = COLORS[len(self.players) % len(COLORS)]
        self.players[peer] = {"name": clean_name(name), "color": color, "pres": None, "base": None}
        self.stats.setdefault(self.players[peer]["name"], {"created": 0, "edited": 0, "deleted": 0})
        self._feed(f"{self.players[peer]['name']} ist beigetreten")
        # A joining game receives every live object (fresh park or resumed session).
        return [(peer, self.upsert_line(gid)) for gid in sorted(self.objects)]

    def leave(self, peer):
        player = self.players.pop(peer, None)
        if player:
            self._feed(f"{player['name']} hat die Sitzung verlassen")

    def presence(self, peer, pres):
        if peer in self.players:
            self.players[peer]["pres"] = pres

    def baseline(self, peer, count):
        if peer in self.players:
            self.players[peer]["base"] = int(count)

    def baseline_mismatch(self):
        counts = {p["base"] for p in self.players.values() if p["base"] is not None}
        return len(counts) > 1

    # -- helpers
    def _feed(self, text):
        self.feed.append({"t": time.time(), "text": text})
        del self.feed[:-60]

    def _name(self, peer):
        return self.players.get(peer, {}).get("name", peer)

    def _count(self, peer, key):
        self.stats.setdefault(self._name(peer), {"created": 0, "edited": 0, "deleted": 0})[key] += 1

    def upsert_line(self, gid):
        s = self.objects[gid]
        return "|".join(["U", gid, clean_name(s["last"]), str(s["rev"]), s["res"],
                         *map(num, s["p"]), *map(num, s["q"]), num(s["s"])])

    def _others(self, peer, line):
        return [(p, line) for p in self.players if p != peer]

    def _restore(self, peer, gid, reason):
        self.conflicts += 1
        out = [(peer, f"R|{gid}|{reason}")]
        if gid in self.objects:
            out.append((peer, self.upsert_line(gid)))
            holder = self.objects[gid]["last"]
            self._feed(f"{self._name(peer)}: Änderung verworfen, {holder} hat das Objekt gerade bearbeitet")
        else:
            out.append((peer, f"D|{gid}|host|0"))
            self._feed(f"{self._name(peer)}: Objekt wurde bereits gelöscht")
        return out

    # -- changes from a player's game
    def up(self, peer, part, gid, rev, res, p, q, s):
        if not RESOURCE.match(res) or (gid and not GID.match(gid)):
            raise ProtocolError("Ungültige Objektdaten.")
        p, q, (s,) = finite(p), finite(q, 2), finite([s], 1000)
        name = self._name(peer)
        state = {"res": res, "p": p, "q": q, "s": s, "last": name}
        if not gid:
            self.counter += 1
            gid = f"{peer}-{self.counter}"
            state.update(rev=1, creator=name)
            self.objects[gid] = state
            self._count(peer, "created")
            self._feed(f"{name} hat {res} platziert")
        elif gid in self.objects:
            current = self.objects[gid]
            if rev != current["rev"]:
                return self._restore(peer, gid, "veraltet")
            state.update(rev=current["rev"] + 1, creator=current.get("creator", "Park"))
            self.objects[gid] = state
            self._count(peer, "edited")
            self._feed(f"{name} hat {res} bearbeitet")
        elif gid in self.tombstones:
            return self._restore(peer, gid, "geloescht")
        elif gid.startswith("P") and rev == 0:
            # First change to an object that existed in the shared base park.
            state.update(rev=1, creator="Park")
            self.objects[gid] = state
            self._count(peer, "edited")
            self._feed(f"{name} hat {res} bearbeitet")
        else:
            return [(peer, f"R|{gid}|unbekannt")]
        self.changed = True
        line = self.upsert_line(gid)
        return [(peer, f"M|{gid}|{int(part)}|{state['rev']}")] + self._others(peer, line)

    def delete(self, peer, part, gid, rev):
        name = self._name(peer)
        if not gid:
            return []
        if not GID.match(gid):
            raise ProtocolError("Ungültige Objekt-ID.")
        if gid in self.objects:
            if rev != self.objects[gid]["rev"]:
                return self._restore(peer, gid, "veraltet")
            res = self.objects.pop(gid)["res"]
        elif gid.startswith("P") and rev == 0 and gid not in self.tombstones:
            res = "Parkobjekt"
        else:
            return self._restore(peer, gid, "unbekannt") if gid in self.tombstones else []
        self.tombstones[gid] = rev + 1
        self._count(peer, "deleted")
        self._feed(f"{name} hat {res} gelöscht")
        self.changed = True
        return [(peer, f"M|{gid}|{int(part)}|0")] + self._others(peer, f"D|{gid}|{clean_name(name)}|{rev + 1}")

    def snapshot(self):
        return {
            "players": [{"peer": k, **v} for k, v in self.players.items()],
            "stats": self.stats,
            "feed": self.feed[-25:],
            "objects": [{"gid": g, "res": s["res"], "p": s["p"], "creator": s.get("creator", "?"),
                         "last": s["last"], "rev": s["rev"]} for g, s in self.objects.items()],
            "conflicts": self.conflicts,
            "baseline_mismatch": self.baseline_mismatch(),
        }

    def to_file(self, path):
        data = {"version": 1, "objects": self.objects, "tombstones": self.tombstones,
                "stats": self.stats, "counter": self.counter}
        tmp = Path(path).with_suffix(".tmp")
        tmp.write_text(json.dumps(data, indent=1), encoding="utf-8")
        tmp.replace(path)

    @classmethod
    def from_file(cls, path):
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        authority = cls(data.get("objects", {}), data.get("stats", {}))
        authority.tombstones = data.get("tombstones", {})
        authority.counter = data.get("counter", 0)
        for gid, s in authority.objects.items():
            if not GID.match(gid) or not RESOURCE.match(s["res"]):
                raise ProtocolError("Sitzungsdatei ungültig.")
            finite(s["p"]); finite(s["q"], 2); finite([s["s"]], 1000)
        return authority


# --------------------------------------------------------------------------------------
# GameLink: talks to one running PC2 test copy through its diagnostic log and inbox.

SYNC_LINE = re.compile(r"\[PC2CoopSync\] (sync:[a-z-]+)\|?(.*)$")


def parse_game_line(line):
    """Turn one sync.lua log line into an event dict, or None."""
    match = SYNC_LINE.search(line.rstrip("\r"))
    if not match:
        return None
    kind, rest = match[1], match[2].split("|") if match[2] else []
    try:
        if kind == "sync:up" and len(rest) == 12:
            return {"t": "up", "part": int(rest[0]), "gid": rest[1], "rev": int(rest[2]), "res": rest[3],
                    "p": [float(v) for v in rest[4:7]], "q": [float(v) for v in rest[7:11]],
                    "s": float(rest[11]) if rest[11] else 1.0}
        if kind == "sync:del" and len(rest) == 3:
            return {"t": "del", "part": int(rest[0]), "gid": rest[1], "rev": int(rest[2] or 0)}
        if kind == "sync:pres" and len(rest) == 8:
            return {"t": "pres", "p": [float(v) for v in rest[0:3]], "ypr": [float(rest[3]), float(rest[4])],
                    "zoom": float(rest[5]), "mode": rest[6][:32], "act": rest[7][:16]}
        if kind == "sync:applied" and rest:
            return {"t": "applied", "seq": int(rest[0])}
        if kind == "sync:baseline" and rest:
            return {"t": "baseline", "count": int(rest[0])}
        if kind == "sync:ready":
            return {"t": "ready", "name": rest[0] if rest else "?"}
        if kind in ("sync:not-ready", "sync:stopped"):
            return {"t": "not-ready"}
        if kind in ("sync:apply-error", "sync:rejected", "sync:read-error", "sync:hook-error", "sync:tick-error"):
            return {"t": "warning", "text": f"{kind} {'|'.join(rest)}"[:200]}
    except ValueError:
        return {"t": "warning", "text": f"Unlesbare Spielzeile: {line[:120]}"}
    return None


class GameLink:
    """Finds the PC2 process with the probe, tails its log and feeds its inbox."""

    def __init__(self, game_dir, on_event):
        self.game_dir = Path(game_dir)
        self.mod_dir = self.game_dir / "Win64" / "ovldata" / "PC2CoopProbe"
        self.on_event = on_event
        self.lock = threading.RLock()
        self.pid = None
        self.log = None
        self.offset = 0
        self.partial = ""
        self.seq = 0
        self.applied = 0
        self.ops = []          # (seq, line) not yet applied by the game
        self.oneshots = []
        self.dirty = False
        self.ready = False
        self.closed = False
        threading.Thread(target=self._run, daemon=True).start()

    def _discover(self):
        logs = sorted(self.mod_dir.glob("pc2coop-diagnostic-*.log"), key=lambda p: p.stat().st_mtime, reverse=True)
        for path in logs[:16]:
            pid = int(re.fullmatch(r"pc2coop-diagnostic-([0-9]+)\.log", path.name)[1])
            if _alive(pid, self.game_dir):
                self.pid, self.log = pid, path
                # Start at the end, but recover whether a park is already loaded.
                text = path.read_bytes().decode("utf-8", errors="replace")
                self.offset = path.stat().st_size
                ready_at = text.rfind("[PC2CoopSync] sync:ready")
                gone_at = max(text.rfind("[PC2CoopSync] sync:not-ready"), text.rfind("park-manager-shutdown"))
                self.ready = ready_at > gone_at
                self.partial = ""
                return True
        return False

    def send_ops(self, lines):
        with self.lock:
            for line in lines:
                self.seq += 1
                kind, _, rest = line.partition("|")
                self.ops.append((self.seq, f"{kind}|{self.seq}|{rest}"))
            self.dirty = True

    def send_control(self, line):
        with self.lock:
            self.oneshots.append(line)
            self.dirty = True

    def _flush(self):
        with self.lock:
            if not self.dirty or self.pid is None:
                return
            body, size = [], 0
            for line in self.oneshots + [line for _, line in self.ops]:
                if size + len(line) + 1 > INBOX_LIMIT:
                    break
                body.append(line)
                size += len(line) + 1
            self.oneshots = []
            self.dirty = bool(self.ops)
            target = self.mod_dir / f"pc2coop-inbox-{self.pid}.txt"
            temp = target.with_suffix(".tmp")
            temp.write_bytes((f"{time.time_ns()}|sync\n" + "\n".join(body)).encode("utf-8"))
            temp.replace(target)
            self.last_flush = time.monotonic()

    def _line(self, line):
        event = parse_game_line(line)
        if not event:
            return
        if event["t"] == "applied":
            with self.lock:
                self.applied = max(self.applied, event["seq"])
                self.ops = [(s, l) for s, l in self.ops if s > self.applied]
                self.dirty = True
        elif event["t"] == "ready":
            self.ready = True
        elif event["t"] == "not-ready":
            self.ready = False
        self.on_event(event)

    def _run(self):
        self.last_flush = 0.0
        while not self.closed:
            try:
                if self.pid is None or not _alive(self.pid, self.game_dir):
                    if self.pid is not None:
                        self.pid, self.ready = None, False
                        self.on_event({"t": "not-ready"})
                    self._discover()
                if self.log is not None and self.pid is not None:
                    with self.log.open("rb") as stream:
                        stream.seek(self.offset)
                        raw = stream.read(512 * 1024)
                    self.offset += len(raw)
                    self.partial += raw.decode("utf-8", errors="replace")
                    lines = self.partial.split("\n")
                    self.partial = lines.pop()[-8192:]
                    for line in lines:
                        self._line(line)
                # The game polls every few frames and only reads a changed file.
                if time.monotonic() - self.last_flush > 0.35:
                    self._flush()
            except OSError as exc:
                self.on_event({"t": "warning", "text": f"Spielverbindung: {exc}"[:200]})
            time.sleep(0.1)

    def close(self):
        self.closed = True


# --------------------------------------------------------------------------------------
# Network host and client.

class HostServer:
    def __init__(self, authority, port=DEFAULT_PORT, bind="0.0.0.0", key=None, session_file=None):
        self.authority = authority
        self.key = key or secrets.token_urlsafe(18)
        self.session_file = session_file
        self.lock = threading.RLock()
        self.wires = {}
        self.next_peer = 0
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind((bind, port))
        self.port = self.sock.getsockname()[1]
        self.sock.listen(MAX_PEERS)
        self.closed = False
        threading.Thread(target=self._accept, daemon=True).start()
        threading.Thread(target=self._heartbeat, daemon=True).start()

    def _accept(self):
        while not self.closed:
            try:
                sock, _ = self.sock.accept()
            except OSError:
                return
            threading.Thread(target=self._serve, args=(sock,), daemon=True).start()

    def _deliver(self, deliveries):
        by_peer = {}
        for peer, line in deliveries:
            by_peer.setdefault(peer, []).append(line)
        for peer, lines in by_peer.items():
            wire = self.wires.get(peer)
            for i in range(0, len(lines), 40):
                try:
                    if wire:
                        wire.send({"t": "ops", "lines": lines[i:i + 40]})
                except (OSError, ProtocolError):
                    pass

    def _broadcast_state(self):
        with self.lock:
            state = {"t": "state", **self.authority.snapshot()}
            wires = list(self.wires.values())
        raw = json.dumps(state)
        if len(raw) > MAX_FRAME - 200:
            state["objects"] = state["objects"][-60:]
        for wire in wires:
            try:
                wire.send(state)
            except (OSError, ProtocolError):
                pass

    def _heartbeat(self):
        while not self.closed:
            time.sleep(0.5)
            self._broadcast_state()
            with self.lock:
                if self.session_file and self.authority.changed:
                    self.authority.changed = False
                    try:
                        self.authority.to_file(self.session_file)
                    except OSError:
                        pass

    def _serve(self, sock):
        wire = Wire(sock)
        peer = None
        try:
            sock.settimeout(15)
            hello = wire.receive()
            if (hello.get("t") != "hello" or hello.get("protocol") != PROTOCOL
                    or not isinstance(hello.get("key"), str) or not hello["key"].isascii()
                    or not hmac.compare_digest(hello["key"], self.key)
                    or not bounded_text(hello.get("name"), 32)):
                wire.send({"t": "error", "text": "Raumschlüssel oder Version falsch."})
                return
            sock.settimeout(None)
            with self.lock:
                if len(self.wires) >= MAX_PEERS:
                    wire.send({"t": "error", "text": "Raum ist voll."})
                    return
                self.next_peer += 1
                peer = f"p{self.next_peer}"
                self.wires[peer] = wire
                snapshot = self.authority.join(peer, hello["name"])
                wire.send({"t": "welcome", "peer": peer, "color": self.authority.players[peer]["color"]})
                self._deliver(snapshot)
            while True:
                message = wire.receive()
                with self.lock:
                    self._handle(peer, message)
        except (OSError, EOFError, ProtocolError, ValueError, KeyError, TypeError):
            pass
        finally:
            with self.lock:
                if peer:
                    self.wires.pop(peer, None)
                    self.authority.leave(peer)
            wire.close()

    def _handle(self, peer, m):
        kind = m.get("t")
        a = self.authority
        if kind == "up":
            self._deliver(a.up(peer, int(m["part"]), str(m["gid"]), int(m["rev"]), str(m["res"]),
                               list(m["p"]), list(m["q"]), float(m["s"])))
        elif kind == "del":
            self._deliver(a.delete(peer, int(m["part"]), str(m["gid"]), int(m["rev"])))
        elif kind == "pres":
            a.presence(peer, {"p": finite(m["p"]), "ypr": finite(m["ypr"]), "zoom": finite([m["zoom"]])[0],
                              "mode": str(m["mode"])[:32], "act": str(m["act"])[:16], "t": time.time()})
        elif kind == "baseline":
            a.baseline(peer, int(m["count"]))

    def close(self):
        self.closed = True
        try:
            self.sock.close()
        except OSError:
            pass
        for wire in list(self.wires.values()):
            wire.close()


class Client:
    """One player's connection: game events up, ordered ops down."""

    def __init__(self, address, port, key, name, game):
        self.name = clean_name(name)
        self.game = game
        self.state = {}
        self.peer = None
        self.color = None
        self.error = ""
        self.warnings = []
        self.lock = threading.Lock()
        sock = socket.create_connection((address, int(port)), timeout=10)
        sock.settimeout(None)
        self.wire = Wire(sock)
        self.wire.send({"t": "hello", "protocol": PROTOCOL, "key": key, "name": self.name})
        welcome = self.wire.receive()
        if welcome.get("t") != "welcome":
            self.wire.close()
            raise ProtocolError(welcome.get("text", "Verbindung abgewiesen."))
        self.peer, self.color = welcome["peer"], welcome["color"]
        self.closed = False
        threading.Thread(target=self._run, daemon=True).start()

    def game_event(self, event):
        """Called by the GameLink for every parsed game line."""
        kind = event["t"]
        try:
            if kind in ("up", "del", "pres", "baseline"):
                self.wire.send({k: v for k, v in event.items()})
            elif kind == "ready":
                self.game.send_control(f"S|{self.name}")
            elif kind == "warning":
                with self.lock:
                    self.warnings = (self.warnings + [event["text"]])[-10:]
        except (OSError, ProtocolError) as exc:
            self.error = f"Verbindung zum Host verloren: {exc}"[:200]

    def jump_to(self, peer):
        player = next((p for p in self.state.get("players", []) if p["peer"] == peer), None)
        if not player or not player.get("pres"):
            raise ProtocolError("Keine Position für diesen Spieler.")
        p, ypr = player["pres"]["p"], player["pres"]["ypr"]
        self.game.send_control("C|" + "|".join(num(v) for v in (*p, *ypr)))

    def _run(self):
        try:
            while not self.closed:
                m = self.wire.receive()
                if m.get("t") == "ops" and isinstance(m.get("lines"), list):
                    self.game.send_ops([str(line)[:400] for line in m["lines"]])
                elif m.get("t") == "state":
                    self.state = m
        except (OSError, EOFError, ProtocolError) as exc:
            if not self.closed:
                self.error = f"Verbindung zum Host verloren: {exc}"[:200]

    def close(self):
        self.closed = True
        self.wire.close()


# --------------------------------------------------------------------------------------
# Local controller with browser UI.

class Controller:
    def __init__(self, game_dir, port=DEFAULT_PORT, sessions_dir=None):
        self.game_dir = Path(game_dir)
        self.port = port
        self.token = secrets.token_urlsafe(24)
        self.sessions_dir = Path(sessions_dir or Path.home() / "Documents" / "PC2Coop" / "sessions")
        self.host = None
        self.client = None
        self.game = GameLink(self.game_dir, self._game_event)
        self.lock = threading.Lock()

    def _game_event(self, event):
        client = self.client
        if client:
            client.game_event(event)
        elif event["t"] == "ready":
            pass

    def action(self, name, data):
        with self.lock:
            if name == "host":
                if self.client:
                    raise ProtocolError("Bereits verbunden.")
                session = str(data.get("session") or "").strip()
                authority = Authority()
                path = None
                if session:
                    if not re.fullmatch(r"[A-Za-z0-9_\- ]{1,40}", session):
                        raise ProtocolError("Sitzungsname: nur Buchstaben, Zahlen, Leerzeichen, - und _.")
                    self.sessions_dir.mkdir(parents=True, exist_ok=True)
                    path = self.sessions_dir / f"{session}.json"
                    if path.is_file():
                        authority = Authority.from_file(path)
                self.host = HostServer(authority, self.port, session_file=path)
                self.client = Client("127.0.0.1", self.host.port, self.host.key, data.get("name", "Host"), self.game)
                if self.game.ready:
                    self.game.send_control(f"S|{self.client.name}")
            elif name == "join":
                if self.client:
                    raise ProtocolError("Bereits verbunden.")
                address = str(data.get("address", "")).strip()
                host, _, port = address.partition(":")
                if not bounded_text(host, 200):
                    raise ProtocolError("Adresse fehlt.")
                self.client = Client(host, int(port or DEFAULT_PORT), str(data.get("key", "")).strip(),
                                     data.get("name", "Spieler"), self.game)
                if self.game.ready:
                    self.game.send_control(f"S|{self.client.name}")
            elif name == "jump":
                if not self.client:
                    raise ProtocolError("Nicht verbunden.")
                self.client.jump_to(str(data.get("peer", "")))
            elif name == "leave":
                if self.client:
                    self.game.send_control("X")
                    self.client.close()
                    self.client = None
                if self.host:
                    self.host.close()
                    self.host = None
            else:
                raise ProtocolError("Unbekannte Aktion.")

    def state(self):
        client = self.client
        return {
            "game": {"pid": self.game.pid, "ready": self.game.ready, "pending": len(self.game.ops)},
            "connected": bool(client and not client.error),
            "peer": client.peer if client else None,
            "error": client.error if client else "",
            "warnings": client.warnings if client else [],
            "hosting": bool(self.host),
            "key": self.host.key if self.host else "",
            "port": self.host.port if self.host else self.port,
            "addresses": local_addresses() if self.host else [],
            "room": client.state if client else {},
        }

    def close(self):
        if self.client:
            self.client.close()
        if self.host:
            self.host.close()
        self.game.close()


def local_addresses():
    addresses = set()
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            addresses.add(info[4][0])
    except OSError:
        pass
    return sorted(a for a in addresses if not a.startswith("127."))


def main(argv=None):
    from .coop_ui import HTML
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-dir", required=True, type=Path)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--no-browser", action="store_true")
    args = parser.parse_args(argv)
    if not (args.game_dir / "Win64" / "ovldata" / "PC2CoopProbe").is_dir():
        parser.error("PC2CoopProbe fehlt in diesem Spielordner. Zuerst INSTALL.cmd ausführen.")
    controller = Controller(args.game_dir, args.port)
    server = serve_http(controller, HTML)
    url = f"http://127.0.0.1:{server.server_port}/"
    print("PC2 Co-op läuft:", url, flush=True)
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
