"""Transient player presence and attribution of accepted model events.

No renderer, UI hooks, Steam identity lookup or persistent park metadata yet.
"""

from __future__ import annotations

from dataclasses import dataclass
import math

from .model import Event, Replica, Transform

ACTIVITIES = frozenset({"idle", "browsing", "building", "moving", "deleting", "away"})
MENUS = frozenset({"unknown", "overview", "scenery", "coasters", "paths", "terrain", "management"})


@dataclass(frozen=True)
class Presence:
    session: str
    peer: str
    sequence: int
    camera: tuple[float, float, float]
    look_at: tuple[float, float, float]
    activity: str = "idle"
    menu: str = "unknown"
    target: str | None = None
    incarnation: int = 1


class PresenceBook:
    """Latest-value, expiring presence, kept out of the durable action log.

    Incarnations are issued by the host when a disconnected peer reconnects.
    Source peer identity and the clock must be bound by a future transport.
    """

    def __init__(self, session: str, peers: set[str], ttl: float = 3.0):
        if not session or not peers or not math.isfinite(ttl) or ttl <= 0:
            raise ValueError("Invalid presence configuration")
        self.session = session
        self.peers = frozenset(peers)
        self.ttl = ttl
        self._active = set(peers)
        self._incarnations = {peer: 1 for peer in peers}
        self._sequences: dict[str, int] = {}
        self._latest: dict[str, tuple[Presence, float]] = {}
        self._last_now = -math.inf

    def _clock(self, now: float) -> None:
        if type(now) not in (int, float) or not math.isfinite(now) or now < self._last_now:
            raise ValueError("Host clock must be finite and monotonic")
        self._last_now = now

    def update(self, sender: str, state: Presence, *, now: float) -> bool:
        self._clock(now)
        if sender not in self._active or state.peer != sender or state.session != self.session:
            return False
        if state.incarnation != self._incarnations[sender] or type(state.sequence) is not int:
            return False
        if state.sequence <= self._sequences.get(sender, 0):
            return False
        if state.activity not in ACTIVITIES or state.menu not in MENUS:
            return False
        if state.target is not None and (not isinstance(state.target, str) or len(state.target) > 128):
            return False
        if not Transform(state.camera, state.look_at).valid():
            return False
        self._sequences[sender] = state.sequence
        self._latest[sender] = (state, now)
        return True

    def visible(self, *, now: float) -> tuple[Presence, ...]:
        self._clock(now)
        return tuple(state for peer, (state, seen) in sorted(self._latest.items())
                     if peer in self._active and now - seen < self.ttl)

    def disconnect(self, peer: str) -> None:
        self._active.discard(peer)
        self._latest.pop(peer, None)

    def reconnect(self, peer: str) -> int:
        if peer not in self.peers or peer in self._active:
            raise ValueError("Peer must be a disconnected room member")
        self._incarnations[peer] += 1
        self._sequences.pop(peer, None)
        self._active.add(peer)
        return self._incarnations[peer]


@dataclass(frozen=True)
class Attribution:
    creator: str
    last_editor: str
    created_sequence: int
    last_sequence: int
    deleted: bool


class ContributionLedger:
    """Counts accepted, ordered events once; creation credit survives edits.

    These are model-command counts, not spent money or a measure of effort.
    History is in memory. Real save/reload metadata remains a separate gate.
    """

    def __init__(self, session: str):
        self.replica = Replica(session)
        self.objects: dict[str, Attribution] = {}
        self._stats: dict[str, dict[str, int]] = {}

    def consume(self, event: Event) -> bool:
        previous = self.objects.get(event.state.object_id)
        if not self.replica.receive(event):
            return False
        operation = "created" if previous is None else "deleted" if event.state.deleted else "edited"
        totals = self._stats.setdefault(event.peer, {"created": 0, "edited": 0, "deleted": 0})
        totals[operation] += 1
        self.objects[event.state.object_id] = Attribution(
            creator=event.peer if previous is None else previous.creator,
            last_editor=event.peer,
            created_sequence=event.sequence if previous is None else previous.created_sequence,
            last_sequence=event.sequence,
            deleted=event.state.deleted,
        )
        return True

    def stats(self, peer: str) -> dict[str, int]:
        return dict(self._stats.get(peer, {"created": 0, "edited": 0, "deleted": 0}))

    def history(self, object_id: str) -> tuple[Event, ...]:
        return tuple(event for event in self.replica.events if event.state.object_id == object_id)
