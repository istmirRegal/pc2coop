"""Host authority and three-player network sessions with simulated games."""
from pathlib import Path
import tempfile
import threading
import time
import unittest

from pc2coop.coop import Authority, Client, HostServer, parse_game_line


def up(a, peer, part, gid, rev, x, res="AQ_Rock_04"):
    return a.up(peer, part, gid, rev, res, [x, 0.0, 0.0], [0.0, 0.0, 0.0, 1.0], 1.0)


class AuthorityTests(unittest.TestCase):
    def setUp(self):
        self.a = Authority()
        for peer, name in (("p1", "Alex"), ("p2", "Sam"), ("p3", "Kim")):
            self.a.join(peer, name)

    def test_create_assigns_gid_acks_author_and_broadcasts(self):
        out = up(self.a, "p1", 988, "", 0, 10)
        self.assertEqual(out[0], ("p1", "M|p1-1|988|1"))
        self.assertEqual({p for p, _ in out[1:]}, {"p2", "p3"})
        self.assertTrue(all(line.startswith("U|p1-1|Alex|1|AQ_Rock_04|10|0|0|") for _, line in out[1:]))
        self.assertEqual(self.a.stats["Alex"]["created"], 1)

    def test_concurrent_edit_of_same_object_rejects_the_stale_one(self):
        up(self.a, "p1", 988, "", 0, 10)
        accepted = up(self.a, "p2", 5, "p1-1", 1, 20)
        self.assertEqual(accepted[0], ("p2", "M|p1-1|5|2"))
        rejected = up(self.a, "p3", 7, "p1-1", 1, 30)
        self.assertEqual(rejected[0], ("p3", "R|p1-1|veraltet"))
        self.assertTrue(rejected[1][1].startswith("U|p1-1|Sam|2|AQ_Rock_04|20|"))
        self.assertEqual(self.a.objects["p1-1"]["p"][0], 20)
        self.assertEqual(self.a.conflicts, 1)

    def test_edit_after_delete_recreates_nothing_and_deletes_again(self):
        up(self.a, "p1", 988, "", 0, 10)
        self.a.delete("p2", 5, "p1-1", 1)
        out = up(self.a, "p3", 7, "p1-1", 1, 30)
        self.assertEqual(out, [("p3", "R|p1-1|geloescht"), ("p3", "D|p1-1|host|0")])

    def test_stale_delete_restores_object(self):
        up(self.a, "p1", 988, "", 0, 10)
        up(self.a, "p2", 5, "p1-1", 1, 20)
        out = self.a.delete("p3", 7, "p1-1", 1)
        self.assertEqual(out[0], ("p3", "R|p1-1|veraltet"))
        self.assertTrue(out[1][1].startswith("U|p1-1|"))
        self.assertIn("p1-1", self.a.objects)

    def test_base_park_objects_are_shared_by_part_id(self):
        out = up(self.a, "p2", 412, "P412", 0, 3)
        self.assertEqual(out[0], ("p2", "M|P412|412|1"))
        self.assertEqual(self.a.objects["P412"]["creator"], "Park")
        out = self.a.delete("p3", 412, "P413", 0)
        self.assertEqual(out[0], ("p3", "M|P413|412|0"))
        self.assertEqual(out[1][1], "D|P413|Kim|1")

    def test_late_joiner_receives_every_live_object(self):
        up(self.a, "p1", 1, "", 0, 1)
        up(self.a, "p2", 2, "", 0, 2)
        self.a.delete("p1", 1, "p1-1", 1)
        snapshot = self.a.join("p4", "Neu")
        self.assertEqual([line.split("|")[1] for _, line in snapshot], ["p2-2"])

    def test_session_file_roundtrip(self):
        up(self.a, "p1", 1, "", 0, 1)
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "s.json"
            self.a.to_file(path)
            b = Authority.from_file(path)
        self.assertEqual(b.objects, self.a.objects)
        self.assertEqual(b.stats["Alex"]["created"], 1)

    def test_bad_input_is_rejected(self):
        with self.assertRaises(ValueError):
            up(self.a, "p1", 1, "", 0, float("nan"))
        with self.assertRaises(ValueError):
            up(self.a, "p1", 1, "", 0, 1, res="bad|name")

    def test_baseline_mismatch(self):
        self.a.baseline("p1", 976)
        self.a.baseline("p2", 976)
        self.assertFalse(self.a.baseline_mismatch())
        self.a.baseline("p3", 12)
        self.assertTrue(self.a.baseline_mismatch())


class ParseTests(unittest.TestCase):
    def test_game_lines(self):
        self.assertEqual(parse_game_line("[PC2CoopSync] sync:up|988||0|AQ_Rock_04|10|5|10|0|0|0|1|1"),
                         {"t": "up", "part": 988, "gid": "", "rev": 0, "res": "AQ_Rock_04",
                          "p": [10.0, 5.0, 10.0], "q": [0.0, 0.0, 0.0, 1.0], "s": 1.0})
        self.assertEqual(parse_game_line("[PC2CoopSync] sync:del|988|p1-1|2")["gid"], "p1-1")
        self.assertEqual(parse_game_line("[PC2CoopSync] sync:applied|7"), {"t": "applied", "seq": 7})
        pres = parse_game_line("[PC2CoopSync] sync:pres|1|2|3|0.5|-0.2|4|StandardOrbit|baut")
        self.assertEqual(pres["act"], "baut")
        self.assertIsNone(parse_game_line("[PC2CoopQA] qa:anything"))


class FakeGame:
    """Mirrors sync.lua: local parts, gid mapping, ordered op stream."""
    def __init__(self):
        self.parts, self.g2l, self.l2g, self.rev = {}, {}, {}, {}
        self.next = 100
        self.client = None
        self.lock = threading.Lock()

    def send_control(self, line):
        pass

    def send_ops(self, lines):
        with self.lock:
            for line in lines:
                f = line.split("|")
                if f[0] == "U":
                    gid = f[1]
                    self.rev[gid] = int(f[3])
                    part = self.g2l.get(gid)
                    if part is None:
                        self.next += 1
                        part = self.next
                    self.parts[part] = (f[4], float(f[5]))
                    self.g2l[gid], self.l2g[part] = part, gid
                elif f[0] == "D":
                    part = self.g2l.pop(f[1], None)
                    if part is not None:
                        self.parts.pop(part, None)
                        self.l2g.pop(part, None)
                elif f[0] == "M":
                    part = int(f[2])
                    if f[3] == "0":
                        self.g2l.pop(f[1], None)
                    else:
                        self.g2l[f[1]], self.l2g[part], self.rev[f[1]] = part, f[1], int(f[3])

    def build(self, x):
        with self.lock:
            self.next += 1
            part = self.next
            self.parts[part] = ("AQ_Rock_04", float(x))
        self.client.game_event({"t": "up", "part": part, "gid": "", "rev": 0, "res": "AQ_Rock_04",
                                "p": [x, 0, 0], "q": [0, 0, 0, 1], "s": 1})
        return part

    def move(self, gid, x):
        with self.lock:
            part = self.g2l[gid]
            self.parts[part] = (self.parts[part][0], float(x))
            rev = self.rev[gid]
        self.client.game_event({"t": "up", "part": part, "gid": gid, "rev": rev, "res": "AQ_Rock_04",
                                "p": [x, 0, 0], "q": [0, 0, 0, 1], "s": 1})

    def remove(self, gid):
        with self.lock:
            part = self.g2l[gid]
            self.parts.pop(part)
            rev = self.rev[gid]
        self.client.game_event({"t": "del", "part": part, "gid": gid, "rev": rev})

    def view(self):
        with self.lock:
            return sorted((self.l2g.get(p, "?"), x) for p, (_, x) in self.parts.items())


class NetworkTests(unittest.TestCase):
    def setUp(self):
        self.host = HostServer(Authority(), port=0, bind="127.0.0.1")
        self.games, self.clients = [], []
        for name in ("Alex", "Sam", "Kim"):
            game = FakeGame()
            client = Client("127.0.0.1", self.host.port, self.host.key, name, game)
            game.client = client
            self.games.append(game)
            self.clients.append(client)

    def tearDown(self):
        for c in self.clients:
            c.close()
        self.host.close()

    def settle(self, predicate, timeout=5):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if predicate():
                return
            time.sleep(0.02)
        self.fail("timeout: " + repr([g.view() for g in self.games]))

    def converged(self, count):
        views = [g.view() for g in self.games]
        return all(v == views[0] for v in views) and len(views[0]) == count and all(gid != "?" for gid, _ in views[0])

    def test_three_players_build_move_delete_and_converge(self):
        a, b, c = self.games
        for i, g in enumerate(self.games):
            for j in range(5):
                g.build(i * 100 + j)
        self.settle(lambda: self.converged(15))
        gid = self.games[0].view()[0][0]
        b.move(gid, 999)
        self.settle(lambda: all((gid, 999.0) in g.view() for g in self.games))
        c.remove(gid)
        self.settle(lambda: self.converged(14))
        stats = self.host.authority.stats
        self.assertEqual(sum(s["created"] for s in stats.values()), 15)
        self.assertEqual(stats["Sam"]["edited"], 1)
        self.assertEqual(stats["Kim"]["deleted"], 1)

    def test_simultaneous_moves_resolve_to_one_state_everywhere(self):
        a, b, c = self.games
        a.build(1)
        self.settle(lambda: self.converged(1))
        gid = a.view()[0][0]
        b.move(gid, 50)
        c.move(gid, 60)   # same base revision as b's move: one of them loses
        self.settle(lambda: self.converged(1) and a.view()[0][1] in (50.0, 60.0))
        self.assertEqual(self.host.authority.conflicts, 1)

    def test_late_joiner_gets_existing_objects_and_wrong_key_is_refused(self):
        self.games[0].build(5)
        self.settle(lambda: self.converged(1))
        late = FakeGame()
        client = Client("127.0.0.1", self.host.port, self.host.key, "Spät", late)
        late.client = client
        self.clients.append(client)
        self.settle(lambda: late.view() == self.games[0].view())
        with self.assertRaises(Exception):
            Client("127.0.0.1", self.host.port, "falsch", "Böse", FakeGame())


if __name__ == "__main__":
    unittest.main()
