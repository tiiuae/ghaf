#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

"""Evaluate flake outputs using nix-eval-jobs with target-family sharding."""

import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

# One worker: the default is one per core, which commits the whole 4-vCPU/16 GB
# `ubuntu-24.04-arm` runner. nix-eval-jobs 2.35.3 made --max-memory-size a real
# budget, so it has to clear the heaviest family -- intel-laptop-extras-debug with
# its installer peaks at about 7.9 GiB under nix-eval-jobs (`nix eval` understates).
EVAL_WORKERS = 1
EVAL_MAX_MEMORY_MB = 12288


def evaluation_groups(
    job_id: int, total_jobs: int, public_config: str
) -> list[tuple[str, str, list[str]]]:
    """Select target families without evaluating their derivations."""
    selected = []
    for output in ("packages", "devShells"):
        names = json.loads(
            subprocess.check_output(
                [
                    "nix",
                    "eval",
                    "--json",
                    f".#{output}",
                    "--override-input",
                    "secure-ab-build-config",
                    f"path:{public_config}",
                    "--apply",
                    "builtins.mapAttrs (_: builtins.attrNames)",
                    "--accept-flake-config",
                ],
                text=True,
            )
        )
        index = 0
        for system, attrs in sorted(names.items()):
            families: dict[str, list[str]] = {}
            for name in attrs:
                family = (
                    "netboot-installer"
                    if name.endswith("-netboot-installer")
                    else name.removesuffix("-installer").removesuffix("-ghafImage")
                )
                families.setdefault(family, []).append(name)
            for family in families.values():
                if index % total_jobs == job_id:
                    selected.append((output, system, family))
                index += 1
    return selected


def run_eval(
    job_id: int, total_jobs: int, public_config: str
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Evaluate each target family in a fresh process."""
    successes: list[dict[str, Any]] = []
    errors: list[dict[str, Any]] = []
    start_time = time.time()
    groups = evaluation_groups(job_id, total_jobs, public_config)
    if not groups:
        return successes, errors

    nix_eval_jobs = (
        Path(
            subprocess.check_output(
                [
                    "nix",
                    "build",
                    "--no-link",
                    "--print-out-paths",
                    "--inputs-from",
                    ".#",
                    "nixpkgs#nix-eval-jobs",
                    "--accept-flake-config",
                ],
                text=True,
            ).strip()
        )
        / "bin"
        / "nix-eval-jobs"
    )

    print(f"[+] Evaluating {len(groups)} target families...", flush=True)

    for output, system, names in groups:
        attrs = " ".join(json.dumps(name) for name in names)
        select_expr = (
            f"flake: {{ {output}.{system} = flake.inputs.nixpkgs.lib.getAttrs "
            f"[ {attrs} ] flake.{output}.{system}; }}"
        )
        cmd = [
            str(nix_eval_jobs),
            "--flake",
            ".#",
            "--override-input",
            "secure-ab-build-config",
            f"path:{public_config}",
            "--no-instantiate",
            "--select",
            select_expr,
            "--force-recurse",
            "--accept-flake-config",
            "--workers",
            str(EVAL_WORKERS),
            "--max-memory-size",
            str(EVAL_MAX_MEMORY_MB),
            "--option",
            "allow-import-from-derivation",
            "false",
        ]
        group_errors = []
        pending = [f"{output}.{system}.{name}" for name in names]
        with subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True) as proc:
            assert proc.stdout is not None
            for line in proc.stdout:
                line = line.strip()
                if not line:
                    continue
                try:
                    result = json.loads(line)
                    elapsed = time.time() - start_time
                    attr = result.get("attr", "?")
                    if attr in pending:
                        pending.remove(attr)
                    if "error" in result:
                        group_errors.append(result)
                        print(f"[{elapsed:6.1f}s] ✗ {attr}", flush=True)
                    else:
                        successes.append(result)
                        print(f"[{elapsed:6.1f}s] ✓ {attr}", flush=True)
                except json.JSONDecodeError:
                    print(line, file=sys.stderr)

            exit_code = proc.wait()
            if exit_code != 0:
                if not pending and not group_errors:
                    pending = [f"{output}.{system}.{names[0]}"]
                group_errors.extend(
                    {
                        "attr": attr,
                        "error": f"Process exited with code {exit_code}",
                    }
                    for attr in pending
                )
        errors.extend(group_errors)

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
    with tempfile.TemporaryDirectory(prefix="ghaf-eval-") as directory:
        public_config = Path(directory)
        shutil.copyfile(
            "config/secure-ab-build-config/config.json", public_config / "config.json"
        )
        for name in ("PK.crt", "KEK.crt", "db.crt"):
            shutil.copyfile(
                Path("modules/reference/org/secureboot-keys") / name, public_config / name
            )
        # RFC 8032 section 7.1 test key: public trust for evaluation only.
        (public_config / "update.pub").write_bytes(
            bytes.fromhex(
                "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
            )
        )
        successes, errors = run_eval(job_id, total_jobs, str(public_config))
    elapsed = time.time() - start_time
    print_results(successes, errors, elapsed)
    sys.stdout.flush()

    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
