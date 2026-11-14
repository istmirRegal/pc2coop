from dataclasses import replace
import math
import unittest

from pc2coop.leases import LeaseBook
from pc2coop.model import Command, Host, ProtocolError, Replica, Transform
from pc2coop.social import ContributionLedger, Presence, PresenceBook

PEERS = {"A", "B", "C"}
ORIGIN = Transform((0, 0, 0), (0, 0, 0))
MOVED = Transform((10, 3, 20), (0, 90, 0))


class LeaseTests(unittest.TestCase):
    def setUp(self):
        self.leases = LeaseBook("park", PEERS, ttl=2)
        self.host = Host("park", PEERS, {"prop"}, leases=self.leases)
        for peer in sorted(PEERS):
            command = Command("park", peer, "create", peer, "create", 0, "prop", ORIGIN)
            self.assertTrue(self.host.submit(peer, command).accepted)

    def test_three_builders_edit_different_objects_concurrently(self):
        grants = {p: self.leases.acquire(p, (f"object:{p}",), now=0) for p in sorted(PEERS)}
        for peer in sorted(PEERS):
            command = Command("park", peer, "move", peer, "move", 1, transform=MOVED)
            self.assertTrue(self.host.submit(peer, command, lease=grants[peer], now=0.5).accepted)
        for _ in range(3):
            replica = Replica("park")
            for event in self.host.events:
                replica.receive(event)
            self.assertEqual(replica.objects, self.host.objects)

    def test_editing_requires_lease_but_browsing_does_not_lock(self):
        command = Command("park", "B", "move", "A", "move", 1, transform=MOVED)
        self.assertEqual(self.host.submit("B", command, now=0).reason, "edit-lease-required")
        self.assertIsNone(self.leases.holder("object:A", now=0))

    def test_another_builder_cannot_use_holders_token(self):
        grant = self.leases.acquire("A", ("object:A",), now=0)
        command = Command("park", "B", "steal", "A", "move", 1, transform=MOVED)
        self.assertEqual(self.host.submit("B", command, lease=grant, now=1).reason, "edit-lease-required")
        self.assertEqual(self.host.objects["A"].revision, 1)

    def test_group_acquisition_is_all_or_nothing(self):
        self.leases.acquire("A", ("group:station", "object:wall"), now=0)
        self.assertIsNone(self.leases.acquire("B", ("object:free", "object:wall"), now=0))
        self.assertIsNone(self.leases.holder("object:free", now=0))
        self.assertIsNotNone(self.leases.acquire("C", ("object:free",), now=0))

    def test_expired_writer_and_late_release_cannot_affect_new_holder(self):
        old = self.leases.acquire("A", ("object:A",), now=0)
        fresh = self.leases.acquire("B", ("object:A",), now=2)
        self.assertNotEqual(old.token, fresh.token)
        self.assertFalse(self.leases.authorizes("A", old, ("object:A",), now=2))
        self.assertFalse(self.leases.release("A", old))
        self.assertEqual(self.leases.holder("object:A", now=2), "B")
        command = Command("park", "A", "late", "A", "move", 1, transform=MOVED)
        self.assertFalse(self.host.submit("A", command, lease=old, now=2).accepted)

    def test_same_holder_needs_new_token_after_expiration(self):
        old = self.leases.acquire("A", ("object:A",), now=0)
        fresh = self.leases.acquire("A", ("object:A",), now=2)
        self.assertFalse(self.leases.authorizes("A", old, ("object:A",), now=2))
        self.assertTrue(self.leases.authorizes("A", fresh, ("object:A",), now=2))

    def test_renewal_extends_active_lease_and_retry_does_not(self):
        original = self.leases.acquire("A", ("object:A",), now=0)
        self.assertEqual(self.leases.acquire("A", ("object:A",), now=1), original)
        renewed = self.leases.renew("A", original, now=1)
        self.assertEqual(renewed.expires_at, 3)
        self.assertTrue(self.leases.authorizes("A", original, ("object:A",), now=2.5))
        self.assertIsNone(self.leases.renew("A", renewed, now=3))

    def test_disconnect_frees_only_that_builders_resources(self):
        self.leases.acquire("A", ("object:A",), now=0)
        self.leases.acquire("B", ("object:B",), now=0)
        self.leases.disconnect("A", now=1)
        self.assertIsNone(self.leases.holder("object:A", now=1))
        self.assertEqual(self.leases.holder("object:B", now=1), "B")

    def test_retried_accepted_command_keeps_outcome_after_release(self):
        grant = self.leases.acquire("A", ("object:A",), now=0)
        command = Command("park", "A", "move", "A", "move", 1, transform=MOVED)
        outcome = self.host.submit("A", command, lease=grant, now=1)
        self.assertTrue(outcome.accepted)
        self.leases.release("A", grant)
        self.assertEqual(self.host.submit("A", command, now=10), outcome)
        self.assertEqual(self.host.objects["A"].revision, 2)

    def test_other_session_grant_cannot_authorize_an_edit(self):
        grant = self.leases.acquire("A", ("object:A",), now=0)
        self.assertFalse(self.leases.authorizes("A", replace(grant, session="old"), ("object:A",), now=1))

    def test_clock_cannot_run_backwards_or_accept_nan(self):
        self.leases.acquire("A", ("object:A",), now=1)
        for now in (0, math.nan, math.inf):
            with self.subTest(now=now), self.assertRaises(ValueError):
                self.leases.holder("object:A", now=now)

    def test_room_profile_must_match_host(self):
        with self.assertRaises(ProtocolError):
            Host("other", PEERS, {"prop"}, leases=self.leases)


class PresenceTests(unittest.TestCase):
    def setUp(self):
        self.book = PresenceBook("park", PEERS, ttl=3)
        self.state = Presence("park", "A", 1, (10, 20, 30), (15, 0, 30), "building", "scenery", "object:one")

    def test_three_markers_have_independent_positions_and_activities(self):
        for index, peer in enumerate(sorted(PEERS)):
            self.assertTrue(self.book.update(peer, replace(self.state, peer=peer, camera=(index, 10, 0)), now=0))
        self.assertEqual(len(self.book.visible(now=1)), 3)
        self.assertEqual([s.camera[0] for s in self.book.visible(now=1)], [0, 1, 2])

    def test_late_presence_cannot_overwrite_newer_menu_or_camera(self):
        self.book.update("A", replace(self.state, sequence=2, menu="coasters"), now=0)
        self.assertFalse(self.book.update("A", self.state, now=1))
        self.assertEqual(self.book.visible(now=1)[0].menu, "coasters")

    def test_expiry_hides_marker_and_duplicate_does_not_keep_it_alive(self):
        self.book.update("A", self.state, now=0)
        self.assertFalse(self.book.update("A", self.state, now=2.9))
        self.assertEqual(self.book.visible(now=3), ())

    def test_disconnect_and_reconnect_reject_old_incarnation(self):
        self.book.update("A", self.state, now=0)
        self.book.disconnect("A")
        self.assertFalse(self.book.update("A", replace(self.state, sequence=100), now=1))
        generation = self.book.reconnect("A")
        self.assertFalse(self.book.update("A", replace(self.state, sequence=100), now=1))
        self.assertTrue(self.book.update("A", replace(self.state, incarnation=generation), now=1))

    def test_forged_or_wrong_park_presence_is_dropped(self):
        self.assertFalse(self.book.update("B", self.state, now=0))
        self.assertFalse(self.book.update("A", replace(self.state, session="other"), now=0))
        self.assertFalse(self.book.update("stranger", self.state, now=0))

    def test_bad_coordinates_or_activity_are_dropped(self):
        for state in (replace(self.state, camera=(math.nan, 0, 0)), replace(self.state, activity="run-script"),
                      replace(self.state, menu="arbitrary-private-input")):
            self.assertFalse(self.book.update("A", state, now=0))
        self.assertEqual(self.book.visible(now=0), ())

    def test_presence_does_not_create_world_objects_or_action_history(self):
        host = Host("park", PEERS, {"prop"})
        ledger = ContributionLedger("park")
        self.book.update("A", self.state, now=0)
        self.assertEqual(host.objects, {})
        self.assertEqual(ledger.replica.events, [])


class AttributionTests(unittest.TestCase):
    def setUp(self):
        self.host = Host("park", PEERS, {"prop"})
        commands = [
            Command("park", "A", "create", "one", "create", 0, "prop", ORIGIN),
            Command("park", "B", "move", "one", "move", 1, transform=MOVED),
            Command("park", "C", "delete", "one", "delete", 2),
        ]
        self.events = [self.host.submit(command.peer, command).event for command in commands]

    def test_creator_and_last_editor_stay_distinct(self):
        ledger = ContributionLedger("park")
        for event in self.events[:2]:
            ledger.consume(event)
        self.assertEqual(ledger.objects["one"].creator, "A")
        self.assertEqual(ledger.objects["one"].last_editor, "B")
        self.assertEqual(ledger.history("one")[-1].state.transform.position, MOVED.position)

    def test_deletion_and_duplicate_delivery_keep_credits_and_count_once(self):
        ledger = ContributionLedger("park")
        for event in self.events:
            self.assertTrue(ledger.consume(event))
            self.assertFalse(ledger.consume(event))
        self.assertTrue(ledger.objects["one"].deleted)
        self.assertEqual(ledger.objects["one"].creator, "A")
        self.assertEqual(ledger.objects["one"].last_editor, "C")
        self.assertEqual(ledger.stats("A"), {"created": 1, "edited": 0, "deleted": 0})
        self.assertEqual(ledger.stats("B")["edited"], 1)
        self.assertEqual(ledger.stats("C")["deleted"], 1)
        self.assertEqual(len(ledger.history("one")), 3)

    def test_rejected_actions_do_not_enter_statistics(self):
        ledger = ContributionLedger("park")
        rejected = Command("park", "A", "old-move", "one", "move", 1, transform=ORIGIN)
        self.assertFalse(self.host.submit("A", rejected).accepted)
        for event in self.host.events:
            ledger.consume(event)
        self.assertEqual(sum(sum(ledger.stats(peer).values()) for peer in PEERS), 3)


if __name__ == "__main__":
    unittest.main()
