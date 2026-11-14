"""Host-clock edit leases for the offline model, not a game-thread scheduler."""

from __future__ import annotations

from dataclasses import dataclass
import math


@dataclass(frozen=True)
class Lease:
    session: str
    holder: str
    token: int
    resources: tuple[str, ...]
    expires_at: float


class LeaseBook:
    """Atomically reserves a set of resources. Tokens fence off old editors.

    `now` must come from the trusted host's monotonic clock, never a client.
    Callers must expand groups/dependent geometry to their full resource set.
    No in-flight engine operations exist in this synchronous model.
    """

    def __init__(self, session: str, peers: set[str], ttl: float = 10.0):
        if not session or not peers or not math.isfinite(ttl) or ttl <= 0:
            raise ValueError("Invalid lease configuration")
        self.session = session
        self.peers = frozenset(peers)
        self.ttl = ttl
        self._last_now = -math.inf
        self._counter = 0
        self._grants: dict[int, Lease] = {}
        self._owners: dict[str, int] = {}

    def _forget(self, grant: Lease) -> None:
        self._grants.pop(grant.token, None)
        for resource in grant.resources:
            if self._owners.get(resource) == grant.token:
                del self._owners[resource]

    def _advance(self, now: float) -> None:
        if type(now) not in (int, float) or not math.isfinite(now) or now < self._last_now:
            raise ValueError("Host clock must be finite and monotonic")
        self._last_now = now
        for grant in tuple(self._grants.values()):
            if now >= grant.expires_at:
                self._forget(grant)

    def acquire(self, sender: str, resources: tuple[str, ...], *, now: float) -> Lease | None:
        self._advance(now)
        if sender not in self.peers or not resources or not all(
            isinstance(key, str) and 0 < len(key) <= 256 for key in resources
        ):
            raise ValueError("Invalid lease request")
        keys = tuple(sorted(set(resources)))
        occupied = {self._owners[key] for key in keys if key in self._owners}
        if occupied:
            # An identical retry returns the existing grant without extending it.
            if len(occupied) == 1:
                grant = self._grants[next(iter(occupied))]
                if grant.holder == sender and grant.resources == keys:
                    return grant
            return None
        self._counter += 1
        grant = Lease(self.session, sender, self._counter, keys, now + self.ttl)
        self._grants[grant.token] = grant
        self._owners.update({key: grant.token for key in keys})
        return grant

    def authorizes(self, sender: str, grant: Lease | None, resources: tuple[str, ...], *, now: float) -> bool:
        self._advance(now)
        if not isinstance(grant, Lease) or sender not in self.peers or not resources:
            return False
        current = self._grants.get(grant.token)
        return (
            grant.session == self.session and grant.holder == sender
            and current is not None and current.holder == sender
            and all(self._owners.get(key) == current.token for key in resources)
        )

    def renew(self, sender: str, grant: Lease, *, now: float) -> Lease | None:
        if not self.authorizes(sender, grant, grant.resources, now=now):
            return None
        current = self._grants[grant.token]
        renewed = Lease(current.session, current.holder, current.token, current.resources, now + self.ttl)
        self._grants[current.token] = renewed
        return renewed

    def release(self, sender: str, grant: Lease) -> bool:
        current = self._grants.get(grant.token)
        if grant.session != self.session or grant.holder != sender or current is None or current.holder != sender:
            return False
        self._forget(current)
        return True

    def disconnect(self, sender: str, *, now: float) -> None:
        self._advance(now)
        for grant in tuple(self._grants.values()):
            if grant.holder == sender:
                self._forget(grant)

    def holder(self, resource: str, *, now: float) -> str | None:
        self._advance(now)
        token = self._owners.get(resource)
        return None if token is None else self._grants[token].holder
