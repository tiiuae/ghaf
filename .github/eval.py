#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

"""Evaluate flake outputs using nix-eval-jobs with index-based sharding."""

import json
import subprocess
import sys
import time
from typing import Any

SELECT_EXPR = """
flake: let
  lib = flake.inputs.nixpkgs.lib;
  jobId = {job_id};
  totalJobs = {total_jobs};

  # Shard an attrset: keep attrs where (globalIdx + localIdx) mod totalJobs == jobId
  shardAttrs = globalIdx: attrs:
    let
      names = builtins.attrNames attrs;
      selected = lib.imap0 (i: name:
        if lib.mod (globalIdx + i) totalJobs == jobId then name else null
      ) names;
    in lib.getAttrs (builtins.filter (x: x != null) selected) attrs;

  # Apply sharding across all systems for an output type
  shardOutput = outputName:
    let
      output = flake.${{outputName}} or {{}};
      systems = builtins.attrNames output;
      offsets = builtins.foldl' (acc: sys:
        acc // {{ ${{sys}} = acc._idx; _idx = acc._idx + builtins.length (builtins.attrNames output.${{sys}}); }}
      ) {{ _idx = 0; }} systems;
    in builtins.mapAttrs (sys: attrs: shardAttrs offsets.${{sys}} attrs) output;

in {{
  packages = shardOutput "packages";
  devShells = shardOutput "devShells";
}}
"""


def run_eval(
    job_id: int, total_jobs: int
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Run nix-eval-jobs and return (successes, errors)."""
    select_expr = SELECT_EXPR.format(job_id=job_id, total_jobs=total_jobs)

    cmd = [
        "nix",
        "run",
        "--inputs-from",
        ".#",
        "nixpkgs#nix-eval-jobs",
        "--",
        "--flake",
        ".#",
        "--no-instantiate",
        "--select",
        select_expr,
        "--force-recurse",
        "--accept-flake-config",
        "--option",
        "allow-import-from-derivation",
        "false",
    ]

    successes = []
    errors = []
    start_time = time.time()

    print("[+] Starting nix-eval-jobs...", flush=True)

    with subprocess.Popen(
        cmd, stdout=subprocess.PIPE, text=True
    ) as proc:
        assert proc.stdout is not None
        for line in proc.stdout:
            line = line.strip()
            if not line:
                continue
            try:
                result = json.loads(line)
                elapsed = time.time() - start_time
                attr = result.get("attr", "?")
                if "error" in result:
                    errors.append(result)
                    print(f"[{elapsed:6.1f}s] ✗ {attr}")
                else:
                    successes.append(result)
                    print(f"[{elapsed:6.1f}s] ✓ {attr}")
            except json.JSONDecodeError:
                # Not JSON, probably a warning
                print(line, file=sys.stderr)

        exit_code = proc.wait()
        if exit_code != 0 and not errors:
            errors.append({"attr": "nix-eval-jobs", "error": f"Process exited with code {exit_code}"})

    return successes, errors


def print_results(
    successes: list[dict[str, Any]], errors: list[dict[str, Any]], elapsed: float
) -> None:
    """Pretty print evaluation results."""
    print(f"\n{'=' * 60}")
    print(f"Evaluated {len(successes) + len(errors)} attributes in {elapsed:.1f}s")
    print(f"  ✓ {len(successes)} succeeded")
    print(f"  ✗ {len(errors)} failed")

    if errors:
        print(f"\n{'=' * 60}")
        print("Errors:\n")
        for err in errors:
            attr = err.get("attr", "unknown")
            error_msg = err.get("error", "unknown error")
            print(f"  {attr}:")
            # Indent error message
            for line in error_msg.split("\n"):
                print(f"    {line}")
            print()


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <job-id> <total-jobs>", file=sys.stderr)
        return 1

    try:
        job_id = int(sys.argv[1])
        total_jobs = int(sys.argv[2])
    except ValueError:
        print("Error: job-id and total-jobs must be integers", file=sys.stderr)
        return 1

    if job_id < 0 or total_jobs <= 0 or job_id >= total_jobs:
        print("Error: invalid job-id or total-jobs", file=sys.stderr)
        return 1

    print(f"[+] Evaluating flake outputs (job {job_id}/{total_jobs})")

    start_time = time.time()
    successes, errors = run_eval(job_id, total_jobs)
    elapsed = time.time() - start_time
    print_results(successes, errors, elapsed)
    sys.stdout.flush()

    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
