"""Real loopback TCP; fake bridges are explicitly not game-client QA."""
import copy
import json
import os
from pathlib import Path
import socket
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from unittest.mock import patch

from pc2coop.alpha import (Controller, GameBridge, MAX_FRAME, ProtocolError,
                           RoomClient, RoomHost, Wire, coordinates, serve)


def wait_for(predicate, timeout=4):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        # Windows: a file the bridge is writing at this moment cannot be opened (PermissionError);
        # that is "not yet", not a failure (the test failed about one run in six).
        try:
            if predicate():
                return
        except PermissionError:
            pass
        time.sleep(0.01)
    raise AssertionError("Condition timed out")


class FakeGameBridge:
    """In-memory stand-in: confirms operations without running Planet Coaster."""
    def __init__(self, ready=True):
        self.ready = ready
        self.failure = ""
        self.events = []
        self.pid = 123
        self.start_requested = ready
        self.on_ack = lambda *args: None
        self.on_ready = lambda *args: None

    def enqueue(self, event):
        self.events.append(copy.deepcopy(event))
        self.on_ack(event["sequence"], True, "")

    def start_park(self):
        self.ready = True
        self.start_requested = True
        self.on_ready(True)

    def abort(self, reason):
        self.failure = reason
        self.ready = False

    def close(self):
        pass


class AlphaTests(unittest.TestCase):
    def setUp(self):
        self.host = RoomHost(0, bind="127.0.0.1", key="test-key")
        self.clients = []

    def tearDown(self):
        self.host.close()
        for client in self.clients:
            client.close()

    def client(self, name="Spieler", ready=True):
        client = RoomClient("127.0.0.1", self.host.port, self.host.key,
                            name, FakeGameBridge(ready))
        self.clients.append(client)
        return client

    def settled(self, seq, count=None):
        count = count or len(self.clients)
        wait_for(lambda: all(c.sequence == seq and len(c.peers) == count
                            and all(p["applied"] == seq for p in c.peers)
                            for c in self.clients))

    def test_three_tcp_peers_order_create_move_delete_and_duplicate(self):
        peers = [self.client("Spieler " + str(i)) for i in range(3)]
        wait_for(lambda: len(self.host.peers) == 3
                 and all(p["ready"] for p in self.host.peers.values()))
        for index, client in enumerate(peers):
            client.command("create", [10 + index * 10, 5, 10], operation_id="create")
            self.settled(index + 1)
        self.assertEqual(3, len(self.host.objects))
        first = peers[0].peer + ":1"
        peers[0].command("move", [50, 6, 70], first, "move-once")
        self.settled(4)
        peers[0].command("move", [50, 6, 70], first, "move-once")
        time.sleep(0.05)
        self.assertEqual(4, self.host.sequence)
        peers[1].command("delete", object_id=peers[1].peer + ":1")
        self.settled(5)
        for client in peers:
            self.assertEqual(self.host.objects, client.objects)
            self.assertEqual([1, 2, 3, 4, 5],
                             [e["sequence"] for e in client.bridge.events])
        self.assertEqual([50.0, 6.0, 70.0], self.host.objects[first]["position"])

    def test_ownership_prevents_move_and_delete(self):
        owner, other = self.client("Eigentümer"), self.client("Gast")
        wait_for(lambda: len(self.host.peers) == 2
                 and all(p["ready"] for p in self.host.peers.values()))
        owner.command("create", [10, 5, 10])
        self.settled(1)
        oid = owner.peer + ":1"
        other.command("move", [100, 100, 100], oid)
        wait_for(lambda: "eigenen" in other.error)
        self.assertEqual(1, self.host.sequence)
        other.error = ""
        other.command("delete", object_id=oid)
        wait_for(lambda: "eigenen" in other.error)
        self.assertFalse(self.host.objects[oid]["deleted"])

    def test_wrong_key_rejected(self):
        with self.assertRaisesRegex(ProtocolError, "Raumschlüssel"):
            RoomClient("127.0.0.1", self.host.port, "wrong", "Gast", FakeGameBridge())
        self.assertFalse(self.host.peers)

    def test_late_join_rejected_after_first_edit(self):
        client = self.client()
        wait_for(lambda: any(p["ready"] for p in self.host.peers.values()))
        client.command("create", [10, 5, 10])
        self.settled(1)
        with self.assertRaisesRegex(ProtocolError, "Bauen hat begonnen"):
            self.client("Zu spät")

    def test_all_games_must_be_ready(self):
        first, second = self.client("A"), self.client("B", ready=False)
        wait_for(lambda: len(self.host.peers) == 2)
        first.command("create", [10, 5, 10])
        wait_for(lambda: "Testpark" in first.error)
        self.assertEqual(0, self.host.sequence)
        second.bridge.start_park()
        wait_for(lambda: all(p["ready"] for p in self.host.peers.values()))
        first.command("create", [10, 5, 10])
        self.settled(1)

    def test_bad_coordinates_and_operations_are_rejected(self):
        for bad in ([float("nan"), 0, 0], [float("inf"), 0, 0],
                    [True, 0, 0], [10001, 0, 0], [1, 2], "1,2,3"):
            with self.assertRaises(ProtocolError):
                coordinates(bad)
        client = self.client()
        wait_for(lambda: any(p["ready"] for p in self.host.peers.values()))
        client.command("execute", [1, 2, 3])
        wait_for(lambda: "Nur create" in client.error)
        self.assertEqual(0, self.host.sequence)

    def test_dedupe_id_cannot_change_payload(self):
        client = self.client()
        wait_for(lambda: any(p["ready"] for p in self.host.peers.values()))
        client.command("create", [10, 5, 10], operation_id="same")
        self.settled(1)
        client.command("create", [11, 5, 10], operation_id="same")
        wait_for(lambda: "wiederverwendet" in client.error)
        self.assertEqual(1, self.host.sequence)

    def test_disconnect_after_edit_stops_room(self):
        one, two = self.client("A"), self.client("B")
        wait_for(lambda: len(self.host.peers) == 2
                 and all(p["ready"] for p in self.host.peers.values()))
        one.command("create", [10, 5, 10])
        self.settled(1)
        two.close()
        wait_for(lambda: one.fatal)
        with self.assertRaises(ProtocolError):
            one.command("create", [20, 5, 20])
        self.assertTrue(self.host.failure)

    def test_eight_players_maximum(self):
        for i in range(8):
            self.client(str(i))
        wait_for(lambda: len(self.host.peers) == 8)
        with self.assertRaisesRegex(ProtocolError, "Raum voll"):
            self.client("Neun")

    def test_game_failure_freezes_all_peers(self):
        a, b = self.client("A"), self.client("B")
        b.bridge.enqueue = lambda event: b.bridge.on_ack(event["sequence"], False, "readback failed")
        wait_for(lambda: len(self.host.peers) == 2
                 and all(p["ready"] for p in self.host.peers.values()))
        a.command("create", [10, 5, 10])
        wait_for(lambda: a.fatal and b.fatal)
        self.assertIn("readback", a.error)
        self.assertFalse(a.bridge.ready)

    def test_next_event_waits_for_every_game_ack(self):
        a, b = self.client("A"), self.client("B")
        pending = []
        b.bridge.enqueue = pending.append
        wait_for(lambda: len(self.host.peers) == 2
                 and all(p["ready"] for p in self.host.peers.values()))
        a.command("create", [10, 5, 10])
        wait_for(lambda: len(pending) == 1)
        a.command("create", [20, 5, 20])
        wait_for(lambda: "Vorige Aktion" in a.error)
        self.assertEqual(1, self.host.sequence)
        b._ack(1, True, "")
        self.settled(1)
        a.command("create", [20, 5, 20])
        wait_for(lambda: self.host.sequence == 2)

    def test_host_ack_timeout_freezes_room(self):
        client = self.client()
        client.bridge.enqueue = lambda event: None
        wait_for(lambda: all(p["ready"] for p in self.host.peers.values()))
        client.command("create", [10, 5, 10])
        wait_for(lambda: self.host.sequence == 1)
        self.host.ack_deadline = time.monotonic() - 1
        wait_for(lambda: client.fatal)
        self.assertIn("65 Sekunden", client.error)


class FrameTests(unittest.TestCase):
    def test_client_rejects_host_object_inbox_injection(self):
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        def hostile():
            sock, _ = listener.accept()
            wire = Wire(sock)
            try:
                wire.receive()
                wire.send({"type": "welcome", "peer": "p1", "sequence": 0})
                wire.receive()
                wire.send({"type": "event", "sequence": 1, "operation": "create",
                           "object": {"id": "p1:1\nnew-test-park", "owner": "p1", "name": "x",
                                      "resource": "AQ_Rock_04", "position": [1, 2, 3], "deleted": False}})
                time.sleep(0.1)
            finally:
                wire.close()
        thread = threading.Thread(target=hostile, daemon=True)
        thread.start()
        bridge = FakeGameBridge()
        client = RoomClient("127.0.0.1", listener.getsockname()[1], "key", "A", bridge)
        try:
            wait_for(lambda: client.fatal)
            self.assertFalse(bridge.events)
            self.assertIn("Ungültiges Objekt", client.error)
        finally:
            client.close()
            listener.close()
            thread.join(1)

    def test_fragmented_frames_and_coalesced_frames(self):
        a, b = socket.socketpair()
        try:
            wire = Wire(a)
            b.sendall(b'{"x":')
            b.sendall(b'1}\n{"x":2}\n')
            self.assertEqual({"x": 1}, wire.receive())
            self.assertEqual({"x": 2}, wire.receive())
        finally:
            a.close()
            b.close()

    def test_oversized_non_object_and_nonfinite_frames_rejected(self):
        for raw in (b"x" * MAX_FRAME, b"[]\n", b'{"x":NaN}\n', b'\xff\n'):
            a, b = socket.socketpair()
            try:
                b.sendall(raw)
                with self.assertRaises(ProtocolError):
                    Wire(a).receive()
            finally:
                a.close()
                b.close()


class BridgeTests(unittest.TestCase):
    def test_pid_bound_inbox_explicit_newpark_ack_and_error_stop(self):
        with tempfile.TemporaryDirectory() as temp:
            game = Path(temp)
            mod = game / "Win64" / "ovldata" / "PC2CoopProbe"
            mod.mkdir(parents=True)
            log = mod / f"pc2coop-diagnostic-{os.getpid()}.log"
            log.write_text("[PC2CoopLive] live:ready\n", encoding="utf-8")
            with patch("pc2coop.alpha._alive", return_value=True):
                bridge = GameBridge(game)
                results = []
                bridge.on_ack = lambda *args: results.append(args)
                try:
                    wait_for(lambda: bridge.log is not None)
                    self.assertFalse(bridge.ready, "Old readiness must not activate this session")
                    bridge.start_park()
                    inbox = mod / f"pc2coop-inbox-{os.getpid()}.txt"
                    self.assertRegex(inbox.read_text(), r"^[0-9]+\|new-test-park$")
                    self.assertFalse(bridge.ready)
                    with log.open("a", encoding="utf-8") as f:
                        f.write("[PC2CoopLive] live:ready\n")
                    wait_for(lambda: bridge.ready)
                    event = {"sequence": 1, "operation": "create",
                             "object": {"id": "p1:1", "position": [10, 5, 10]}}
                    bridge.enqueue(event)
                    wait_for(lambda: "|live|1|create|p1:1|10|5|10" in inbox.read_text())
                    with log.open("a", encoding="utf-8") as f:
                        f.write("[PC2CoopLive] live:ack:1:ok\n")
                    wait_for(lambda: results == [(1, True, "")])
                    bridge.enqueue({**event, "sequence": 2, "operation": "move"})
                    wait_for(lambda: "|live|2|move|" in inbox.read_text())
                    with log.open("a", encoding="utf-8") as f:
                        f.write("[PC2CoopLive] live:ack:2:error:bad position\n")
                    wait_for(lambda: bridge.failure)
                    self.assertFalse(bridge.ready)
                    self.assertEqual((2, False, "bad position"), results[-1])
                finally:
                    bridge.close()


class HttpTests(unittest.TestCase):
    def test_localhost_ui_token_and_state(self):
        controller = Controller(Path("unused"), bridge=FakeGameBridge(False))
        server = serve(controller)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f"http://127.0.0.1:{server.server_port}"
        try:
            with urllib.request.urlopen(base) as response:
                html = response.read().decode()
            self.assertIn("LAN-Alpha", html)
            self.assertIn(controller.token, html)
            request = urllib.request.Request(base + "/api/start", data=b"{}",
                                             headers={"Content-Type": "application/json"})
            with self.assertRaises(urllib.error.HTTPError) as context:
                urllib.request.urlopen(request)
            self.assertEqual(403, context.exception.code)
            request = urllib.request.Request(base + "/api/state", headers={"Host": "evil.example"})
            with self.assertRaises(urllib.error.HTTPError) as context:
                urllib.request.urlopen(request)
            self.assertEqual(403, context.exception.code)
            with urllib.request.urlopen(base + "/api/state") as response:
                self.assertFalse(json.load(response)["connected"])
        finally:
            server.shutdown()
            server.server_close()
            controller.close()


if __name__ == "__main__":
    unittest.main()
