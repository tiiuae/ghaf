#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
"""Compare two collect-logs.sh snapshots and report only what is new.

A Ghaf boot logs plenty of errors that have always been there. Reading a fresh journal
cold, you cannot tell those from the one line your change actually broke. Diffing against
a known-good snapshot answers the question you actually have: what is different now?

Lines are normalised before comparison — timestamps, PIDs, store hashes and similar vary
between boots without meaning anything, and comparing them raw makes every line look new.

Exit status is 1 when new problems are found, so a loop can branch on it.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# Volatile fragments: identical events differ here between boots, so blank them out.
NORMALISERS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"^\w{3}\s+\d+\s+\d{2}:\d{2}:\d{2}\s+"), ""),  # syslog timestamp
    (
        re.compile(
            r"^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}[.,]?\d*(?:[+-]\d{2}:?\d{2}|Z)?\s+"
        ),
        "",
    ),
    # The same again but UNANCHORED, because structured loggers embed their own
    # timestamp inside the message: givc, spire, docker and most Go services all
    # emit `time="2026-08-03T10:45:50Z" level=warning msg=...`. The anchored rule
    # above only strips journald's leading stamp, so those lines stayed unique
    # across boots and every one of them was reported as new.
    (
        re.compile(
            r"\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?(?:[+-]\d{2}:?\d{2}|Z)?"
        ),
        "TIMESTAMP",
    ),
    (re.compile(r"\[\s*\d+\.\d+\]"), "[TIME]"),  # kernel monotonic stamp
    (re.compile(r"\[\d+\]"), "[PID]"),
    (re.compile(r"/nix/store/[a-z0-9]{32}-"), "/nix/store/HASH-"),
    (re.compile(r"\b[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\b"), "UUID"),
    (re.compile(r"\b(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b"), "MAC"),
    (re.compile(r"\b0x[0-9a-fA-F]+\b"), "0xADDR"),
    (re.compile(r"\bpid=\d+"), "pid=N"),
    (re.compile(r"\bport \d+\b"), "port N"),
]

# What counts as worth surfacing when not asked for everything.
INTERESTING = re.compile(
    r"error|fail|fatal|panic|oops|refus|denied|timed? ?out|timeout|cannot|unable|"
    r"segfault|core-dump|not found|missing|degraded|unhealthy|traceback",
    re.IGNORECASE,
)

# Known-noisy patterns that recur on healthy systems. Kept deliberately short: every entry
# here is a chance to hide a real regression, so add only what you have confirmed benign.
BENIGN = re.compile(
    r"Using degraded feature set|"  # systemd-resolved probing DNS transports
    r"Expandable variables must be wrapped|"  # pam_env on ghaf's PATH
    r"Failed to connect to bus: No medium|"
    r"Deactivated successfully",
    re.IGNORECASE,
)


def normalise(line: str) -> str:
    out = line.rstrip("\n")
    for pattern, repl in NORMALISERS:
        out = pattern.sub(repl, out)
    return out.strip()


def load(path: Path) -> set[str]:
    if not path.is_file():
        return set()
    with path.open(encoding="utf-8", errors="replace") as fh:
        return {normalise(line) for line in fh}


def new_lines(old: Path, new: Path, show_all: bool) -> list[str]:
    baseline = load(old)
    if not new.is_file():
        return []
    seen: set[str] = set()
    result: list[str] = []
    with new.open(encoding="utf-8", errors="replace") as fh:
        for line in fh:
            norm = normalise(line)
            if not norm or norm in baseline or norm in seen:
                continue
            if not show_all and (not INTERESTING.search(norm) or BENIGN.search(norm)):
                continue
            seen.add(norm)
            result.append(line.rstrip("\n"))
    return result


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("old", type=Path, help="known-good snapshot directory")
    ap.add_argument("new", type=Path, help="snapshot to examine")
    ap.add_argument(
        "--all", action="store_true", help="report every new line, not just problems"
    )
    ap.add_argument(
        "--max-per-file", type=int, default=40, help="cap per file (default 40)"
    )
    args = ap.parse_args()

    for d in (args.old, args.new):
        if not d.is_dir():
            print(f"Not a snapshot directory: {d}", file=sys.stderr)
            return 2

    vms = sorted(p.name for p in args.new.iterdir() if p.is_dir())
    if not vms:
        print(f"No per-VM directories under {args.new}", file=sys.stderr)
        return 2

    findings = 0

    # Unit state first: a unit that fails now and didn't before is the headline, and is
    # far more actionable than any single journal line.
    print("## Units failing now but not before\n")
    unit_regressions = False
    for vm in vms:
        before = load(args.old / vm / "failed-units.txt")
        after_path = args.new / vm / "failed-units.txt"
        if not after_path.is_file():
            continue
        with after_path.open(encoding="utf-8", errors="replace") as fh:
            for line in fh:
                norm = normalise(line)
                if norm and norm not in before:
                    print(f"- **{vm}**: {line.strip()}")
                    unit_regressions = True
                    findings += 1
    if not unit_regressions:
        print("_none_")
    print()

    # Anything that stopped answering entirely.
    for vm in vms:
        if (args.new / vm / "UNREACHABLE.txt").is_file() and not (
            args.old / vm / "UNREACHABLE.txt"
        ).is_file():
            print(
                f"> **{vm} became unreachable** — it answered in the baseline snapshot.\n"
            )
            findings += 1

    print("## New log lines\n")
    any_lines = False
    for vm in vms:
        for name in ("journal-boot.txt", "dmesg.txt"):
            lines = new_lines(args.old / vm / name, args.new / vm / name, args.all)
            if not lines:
                continue
            any_lines = True
            findings += len(lines)
            shown = lines[: args.max_per_file]
            print(f"### {vm} / {name} — {len(lines)} new\n")
            print("```")
            for line in shown:
                print(line)
            print("```")
            if len(lines) > len(shown):
                # Say what was dropped: a silent cap reads as "that was everything".
                print(
                    f"_… {len(lines) - len(shown)} further new lines not shown "
                    f"(raise --max-per-file to see them)_"
                )
            print()
    if not any_lines:
        print("_none_\n")

    print(
        f"---\n{findings} new item(s). Baseline: `{args.old}`  Compared: `{args.new}`"
    )
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
