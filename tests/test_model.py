from dataclasses import replace
import math
import random
import unittest

from pc2coop.model import Command, Host, ProtocolError, Replica, Transform, digest

ORIGIN = Transform((0, 0, 0), (0, 0, 0))
MOVED = Transform((20.5, 1.25, -3), (0, 90, 0), 1.5)


class ModelTests(unittest.TestCase):
    def setUp(self):
        self.host = Host("park-epoch-1", {"A", "B"}, {"test.base.prop"})
        self.create = Command("park-epoch-1", "A", "action-1", "object-1", "create", 0,
                              "test.base.prop", ORIGIN)

    def add(self):
        result = self.host.submit("A", self.create)
        self.assertTrue(result.accepted)
        return result

    def test_create_move_delete_converge_on_two_replicas(self):
        self.add()
        move = Command("park-epoch-1", "B", "action-2", "object-1", "move", 1, transform=MOVED)
        delete = Command("park-epoch-1", "A", "action-3", "object-1", "delete", 2)
        self.assertTrue(self.host.submit("B", move).accepted)
        self.assertTrue(self.host.submit("A", delete).accepted)
        for replica in (Replica(self.host.session), Replica(self.host.session)):
            for event in self.host.events:
                self.assertTrue(replica.receive(event))
                self.assertFalse(replica.receive(event))
            self.assertEqual(replica.objects, self.host.objects)
            self.assertEqual(digest(replica.objects), digest(self.host.objects))
        self.assertTrue(self.host.objects["object-1"].deleted)

    def test_retry_returns_original_outcome_and_no_second_object(self):
        result = self.add()
        self.assertEqual(self.host.submit("A", self.create), result)
        self.assertEqual(len(self.host.events), 1)
        self.assertEqual(len(self.host.objects), 1)

    def test_move_retry_does_not_become_revision_conflict(self):
        self.add()
        command = Command(self.host.session, "B", "move-1", "object-1", "move", 1, transform=MOVED)
        accepted = self.host.submit("B", command)
        self.assertTrue(accepted.accepted)
        self.assertEqual(self.host.submit("B", command), accepted)
        self.assertEqual(len(self.host.events), 2)

    def test_reused_action_id_with_new_payload_is_rejected(self):
        self.add()
        result = self.host.submit("A", replace(self.create, transform=MOVED))
        self.assertEqual(result.reason, "action-id-reused")
        self.assertEqual(self.host.objects["object-1"].transform, ORIGIN)

    def test_simultaneous_edits_have_one_winner(self):
        self.add()
        first = Command(self.host.session, "A", "move-A", "object-1", "move", 1, transform=MOVED)
        second = replace(first, peer="B", action="move-B", transform=ORIGIN)
        self.assertTrue(self.host.submit("A", first).accepted)
        self.assertEqual(self.host.submit("B", second).reason, "revision-conflict")
        self.assertEqual(self.host.objects["object-1"].transform, MOVED)

    def test_rejected_outcome_stays_rejected_on_retry(self):
        move = Command(self.host.session, "B", "too-early", "object-1", "move", 1, transform=MOVED)
        rejected = self.host.submit("B", move)
        self.add()
        self.assertEqual(self.host.submit("B", move), rejected)
        self.assertFalse(rejected.accepted)

    def test_sender_cannot_impersonate_another_peer(self):
        self.assertEqual(self.host.submit("B", self.create).reason, "sender-mismatch")
        self.assertEqual(self.host.submit("stranger", self.create).reason, "sender-mismatch")

    def test_old_park_session_is_rejected(self):
        self.assertEqual(self.host.submit("A", replace(self.create, session="old-epoch")).reason, "stale-session")
        self.assertEqual(len(self.host.events), 0)

    def test_asset_not_in_shared_catalogue_is_rejected(self):
        self.assertEqual(self.host.submit("A", replace(self.create, resource="unshared.dlc.prop")).reason, "resource-not-shared")

    def test_deleted_object_cannot_be_recreated_or_moved(self):
        self.add()
        delete = Command(self.host.session, "A", "delete", "object-1", "delete", 1)
        self.assertTrue(self.host.submit("A", delete).accepted)
        self.assertEqual(self.host.submit("A", replace(self.create, action="new-create")).reason, "identity-already-used")
        move = Command(self.host.session, "B", "move-dead", "object-1", "move", 2, transform=MOVED)
        self.assertEqual(self.host.submit("B", move).reason, "object-not-live")

    def test_bad_transforms_never_reach_event_log(self):
        values = (
            Transform((math.nan, 0, 0), (0, 0, 0)),
            Transform((0, 0, 0), (0, math.inf, 0)),
            Transform((0, 0, 0), (0, 0, 0), 0),
            Transform((0, 0), (0, 0, 0)),
            Transform((10**1000, 0, 0), (0, 0, 0)),
            Transform((True, 0, 0), (0, 0, 0)),
        )
        for i, transform in enumerate(values):
            with self.subTest(transform=transform):
                result = self.host.submit("A", replace(self.create, action=f"bad-{i}", transform=transform))
                self.assertEqual(result.reason, "invalid-transform")
        self.assertEqual(self.host.events, [])

    def test_invalid_revision_and_operation_are_rejected(self):
        for revision in (-1, True, "0"):
            with self.subTest(revision=revision):
                host = Host(self.host.session, {"A"}, {"test.base.prop"})
                self.assertEqual(host.submit("A", replace(self.create, expected_revision=revision)).reason, "invalid-revision")
        self.assertEqual(self.host.submit("A", replace(self.create, operation="execute-lua")).reason, "unsupported-operation")

    def test_resource_and_delete_payload_cannot_hide_other_operations(self):
        self.add()
        move = Command(self.host.session, "B", "x", "object-1", "move", 1, "other", MOVED)
        self.assertEqual(self.host.submit("B", move).reason, "resource-change-not-supported")
        delete = Command(self.host.session, "B", "y", "object-1", "delete", 1, transform=MOVED)
        self.assertEqual(self.host.submit("B", delete).reason, "delete-has-transform")

    def test_event_gap_fails_without_changing_replica(self):
        event = self.add().event
        replica = Replica(self.host.session)
        with self.assertRaisesRegex(ProtocolError, "missing-event"):
            replica.receive(replace(event, sequence=2))
        self.assertEqual(replica.objects, {})
        self.assertTrue(replica.receive(event))

    def test_conflicting_duplicate_is_detected(self):
        event = self.add().event
        replica = Replica(self.host.session)
        replica.receive(event)
        with self.assertRaisesRegex(ProtocolError, "conflicting-duplicate"):
            replica.receive(replace(event, state=replace(event.state, transform=MOVED)))

    def test_stale_or_zero_sequence_event_is_rejected(self):
        event = self.add().event
        replica = Replica(self.host.session)
        for bad in (replace(event, session="old"), replace(event, sequence=0)):
            with self.assertRaises(ProtocolError):
                replica.receive(bad)
        self.assertEqual(replica.events, [])

    def test_revision_skip_is_rejected(self):
        event = self.add().event
        replica = Replica(self.host.session)
        replica.receive(event)
        bad = replace(event, sequence=2, action="bad", state=replace(event.state, revision=3))
        with self.assertRaisesRegex(ProtocolError, "invalid-revision-event"):
            replica.receive(bad)

    def test_100_seeded_three_and_four_player_sessions_converge_with_duplicates(self):
        for seed in range(100):
            rng = random.Random(seed)
            peers = ("A", "B", "C") if seed % 2 else ("A", "B", "C", "D")
            host = Host(f"park-{seed}", set(peers), {"test.base.prop"})
            replicas = [Replica(host.session) for _ in peers]
            for index in range(100):
                peer = rng.choice(peers)
                key = f"object-{rng.randrange(12)}"
                previous = host.objects.get(key)
                operation = "create" if previous is None else rng.choice(("move", "move", "delete"))
                revision = 0 if previous is None else previous.revision
                if rng.randrange(5) == 0:
                    revision += 1
                command = Command(
                    host.session, peer, f"action-{index}", key, operation, revision,
                    "test.base.prop" if operation == "create" else None,
                    None if operation == "delete" else Transform((rng.random() * 100, 0, 0), (0, 0, 0)),
                )
                outcome = host.submit(peer, command)
                self.assertEqual(host.submit(peer, command), outcome, f"retry seed={seed}")
                if outcome.accepted:
                    for replica in replicas:
                        self.assertTrue(replica.receive(outcome.event))
                        self.assertFalse(replica.receive(outcome.event))
            for replica in replicas:
                self.assertEqual(replica.objects, host.objects, f"seed={seed}")
                self.assertEqual(len(replica.events), len(host.events))
                self.assertEqual(digest(replica.objects), digest(host.objects))


if __name__ == "__main__":
    unittest.main()
