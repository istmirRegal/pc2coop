"""Offline host/replica model for scenery commands. This does not call the game.

Each object has a logical identity and revision; native Entity/Part IDs never enter
this model. State and deduplication history are in memory only. A future adapter
must commit through PC2 and confirm readback before publishing acceptance.
"""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import math

from .leases import Lease, LeaseBook


class ProtocolError(ValueError):
    pass


def identity(value: str) -> bool:
    return isinstance(value, str) and 0 < len(value) <= 128 and all(
        char.isascii() and (char.isalnum() or char in "_-:.") for char in value
    )


@dataclass(frozen=True)
class Transform:
    position: tuple[float, float, float]
    rotation: tuple[float, float, float]
    scale: float = 1.0

    def valid(self) -> bool:
        return (
            isinstance(self.position, tuple) and len(self.position) == 3
            and isinstance(self.rotation, tuple) and len(self.rotation) == 3
            and all(type(v) in (int, float) and abs(v) <= 1_000_000 and math.isfinite(v)
                    for v in (*self.position, *self.rotation, self.scale))
            and 0 < self.scale <= 1000
        )


@dataclass(frozen=True)
class Command:
    session: str
    peer: str
    action: str
    object_id: str
    operation: str
    expected_revision: int
    resource: str | None = None
    transform: Transform | None = None


@dataclass(frozen=True)
class ObjectState:
    object_id: str
    resource: str
    transform: Transform
    revision: int
    deleted: bool = False


@dataclass(frozen=True)
class Event:
    session: str
    sequence: int
    peer: str
    action: str
    state: ObjectState


@dataclass(frozen=True)
class Outcome:
    accepted: bool
    reason: str
    event: Event | None = None


class Host:
    """Single-threaded model; authenticated sender binding is supplied by caller.

    shared_resources is a test whitelist, not a verified DLC entitlement source.
    Instantiate a fresh session after a park reload; there is no crash recovery.
    """

    def __init__(self, session: str, peers: set[str], shared_resources: set[str], *, leases: LeaseBook | None = None):
        if not identity(session) or not peers or not all(identity(p) for p in peers):
            raise ProtocolError("Invalid session or peers")
        self.session = session
        self.peers = frozenset(peers)
        if leases is not None and (leases.session != session or leases.peers != self.peers):
            raise ProtocolError("Lease room does not match host")
        self.leases = leases
        self.shared_resources = frozenset(shared_resources)
        self.objects: dict[str, ObjectState] = {}
        self.events: list[Event] = []
        self._outcomes: dict[tuple[str, str], tuple[Command, Outcome]] = {}

    def submit(self, sender: str, command: Command, *, lease: Lease | None = None, now: float | None = None) -> Outcome:
        if sender not in self.peers or command.peer != sender:
            return Outcome(False, "sender-mismatch")
        if command.session != self.session:
            return Outcome(False, "stale-session")
        if not all(identity(v) for v in (command.action, command.object_id)):
            return Outcome(False, "invalid-identity")
        key = (sender, command.action)
        previous = self._outcomes.get(key)
        if previous is not None:
            return previous[1] if previous[0] == command else Outcome(False, "action-id-reused")
        if self.leases is not None and command.operation in {"move", "delete"}:
            if now is None or not self.leases.authorizes(sender, lease, (f"object:{command.object_id}",), now=now):
                result = Outcome(False, "edit-lease-required")
                self._outcomes[key] = (command, result)
                return result
        result = self._decide(command)
        self._outcomes[key] = (command, result)
        return result

    def _decide(self, command: Command) -> Outcome:
        if type(command.expected_revision) is not int or command.expected_revision < 0:
            return Outcome(False, "invalid-revision")
        if command.operation not in {"create", "move", "delete"}:
            return Outcome(False, "unsupported-operation")
        existing = self.objects.get(command.object_id)
        if command.operation == "create":
            if existing is not None:
                return Outcome(False, "identity-already-used")
            if command.expected_revision != 0:
                return Outcome(False, "revision-conflict")
            if not isinstance(command.resource, str) or command.resource not in self.shared_resources:
                return Outcome(False, "resource-not-shared")
        else:
            if existing is None or existing.deleted:
                return Outcome(False, "object-not-live")
            if command.expected_revision != existing.revision:
                return Outcome(False, "revision-conflict")
            if command.resource is not None:
                return Outcome(False, "resource-change-not-supported")
        if command.operation != "delete":
            if not isinstance(command.transform, Transform) or not command.transform.valid():
                return Outcome(False, "invalid-transform")
        elif command.transform is not None:
            return Outcome(False, "delete-has-transform")
        state = ObjectState(
            object_id=command.object_id,
            resource=command.resource if existing is None else existing.resource,
            transform=command.transform if command.operation != "delete" else existing.transform,
            revision=1 if existing is None else existing.revision + 1,
            deleted=command.operation == "delete",
        )
        event = Event(self.session, len(self.events) + 1, command.peer, command.action, state)
        self.objects[state.object_id] = state
        self.events.append(event)
        return Outcome(True, "accepted-in-model", event)


class Replica:
    """Consumes ordered host outcomes, with duplicate checks and tombstones.

    Out-of-order events fail closed. A future transport must deliver/recover the
    missing prefix. This is not a lossy-network reliability implementation.
    """

    def __init__(self, session: str):
        self.session = session
        self.objects: dict[str, ObjectState] = {}
        self.events: list[Event] = []

    def receive(self, event: Event) -> bool:
        if event.session != self.session:
            raise ProtocolError("stale-session")
        if type(event.sequence) is not int or event.sequence < 1:
            raise ProtocolError("invalid-sequence")
        if event.sequence <= len(self.events):
            if self.events[event.sequence - 1] != event:
                raise ProtocolError("conflicting-duplicate")
            return False
        if event.sequence != len(self.events) + 1:
            raise ProtocolError("missing-event")
        previous = self.objects.get(event.state.object_id)
        if previous is None:
            if event.state.revision != 1 or event.state.deleted:
                raise ProtocolError("invalid-create-event")
        elif previous.deleted or event.state.revision != previous.revision + 1 or event.state.resource != previous.resource:
            raise ProtocolError("invalid-revision-event")
        if not event.state.transform.valid():
            raise ProtocolError("invalid-transform-event")
        self.objects[event.state.object_id] = event.state
        self.events.append(event)
        return True


def digest(objects: dict[str, ObjectState]) -> str:
    """Canonical model digest, including deletion tombstones."""
    rows = [
        [s.object_id, s.resource, s.revision, s.deleted,
         [float(v) for v in s.transform.position],
         [float(v) for v in s.transform.rotation], float(s.transform.scale)]
        for _, s in sorted(objects.items())
    ]
    return hashlib.sha256(json.dumps(rows, separators=(",", ":"), allow_nan=False).encode()).hexdigest()
