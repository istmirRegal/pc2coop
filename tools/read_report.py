"""Read a PC2Coop problem report (or a single pc2coop-diagnostic-*.log) and print what matters.

    python tools/read_report.py PC2Coop-Problembericht-2026-11-22-1403.txt

Per log: versions and PC, the session code, a timeline of the session's important steps,
every error with its place (FEAT-138), the last snapshot and the recent network events.
Reports from the host and a guest with the same session code belong to the same session.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

TIMELINE = ("net-ready", "session:code", "lobby", "host", "join", "leave", "left", "ended", "rejected", "refuse",
            "park-retry", "needpark", "resync", "desync", "rate-limited", "stage", "welcome", "file:done", "file:error",
            "member:", "frontend-init", "park-manager-init", "sync:ready", "report")
PROBLEM = re.compile(r"(^|[\]|: ])error\||exception\||-error|failed|rejected|refused|not supported", re.IGNORECASE)


def split_logs(text: str) -> list[tuple[str, list[str]]]:
    parts = re.split(r"^======== (.+?) ========$", text, flags=re.MULTILINE)
    if len(parts) == 1:
        return [("log", text.splitlines())]
    return [(parts[i], parts[i + 1].splitlines()) for i in range(1, len(parts), 2)]


def summarise(name: str, lines: list[str]) -> list[str]:
    out = [f"== {name} ({len(lines)} lines)"]
    for line in lines[:40]:
        if line.startswith("system|") or " begin; phase=" in line or "acse.versionNumber" in line:
            out.append("  " + line[:300])
    codes = sorted({m.group(1) for line in lines for m in [re.search(r"session:code\|(\w+)", line)] if m})
    if codes:
        out.append("  session code(s): " + ", ".join(codes))
    out.append("  timeline:")
    shown = 0
    for number, line in enumerate(lines, 1):
        if "[PC2CoopSession]" in line and any(word in line for word in TIMELINE) and "session:snap" not in line \
                and "session:recent" not in line and shown < 120:
            out.append(f"    {number:6} {line[:200]}")
            shown += 1
    problems = [(n, l) for n, l in enumerate(lines, 1) if PROBLEM.search(l) and "net-stage" not in l and "session:recent|" not in l]
    out.append(f"  problems: {len(problems)}")
    for number, line in problems[:60]:
        out.append(f"    {number:6} {line[:500]}")
    snaps = [l for l in lines if "session:snap|" in l]
    if snaps:
        out.append("  last snapshot: " + snaps[-1].split("session:snap|", 1)[1][:300])
    recent = [l for l in lines if "session:recent|" in l]
    if recent:
        out.append("  recent network events (last dump):")
        reason = recent[-1].split("session:recent|", 1)[1].split("|", 1)[0]
        for line in [l for l in recent if f"session:recent|{reason}|" in l][-5:]:
            out.append("    " + line.split(f"session:recent|{reason}|", 1)[1][:400])
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("report", type=Path)
    args = parser.parse_args()
    text = args.report.read_bytes().decode("utf-8-sig", errors="replace").replace("\r\n", "\n")
    head = text.split("\n======== ", 1)[0]
    if head.strip() and "========" in text:
        print("\n".join(head.strip().splitlines()[:6]))
    for name, lines in split_logs(text):
        print("\n".join(summarise(name, lines)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
