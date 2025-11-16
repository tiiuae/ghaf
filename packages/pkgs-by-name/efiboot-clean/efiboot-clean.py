#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
import argparse
import os
import re
import subprocess
import sys

EFI_ENTRY_PATTERN = re.compile(
    r"^Boot(?P<id>[0-9A-Fa-f]{4}).*?GPT,(?P<guid>[0-9a-fA-F-]{36}).*?\)(?P<path>/\\EFI[^\s]*)"
)


def read_efibootmgr():
    """output of efibootmgr"""
    try:
        result = subprocess.run(
            ["efibootmgr"], text=True, capture_output=True, check=True
        )
        return result.stdout
    except subprocess.CalledProcessError as e:
        print(f"[ERR] efibootmgr failed: {e.stderr}", file=sys.stderr)
        sys.exit(1)


def find_invalid_systemd_boot_entries(text: str):
    broken = []
    for line in text.splitlines():
        m = EFI_ENTRY_PATTERN.search(line)
        if not m:
            continue

        boot_id = m.group("id")
        guid = m.group("guid")
        path = m.group("path")

        if "systemd-bootx64.efi" not in path.lower():
            continue

        disk_path = f"/dev/disk/by-partuuid/{guid.lower()}"
        if os.path.exists(disk_path):
            continue

        broken.append({"id": boot_id, "guid": guid, "path": path})

    return broken


def delete_entry(entry_id: str):
    subprocess.run(["efibootmgr", "-q", "-b", entry_id, "-B"], check=True)


def main():
    parser = argparse.ArgumentParser(
        description="Cleanup invalid systemd-boot EFI entries"
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="actually remove entries (default is dry-run)",
    )
    args = parser.parse_args()

    data = read_efibootmgr()
    broken = find_invalid_systemd_boot_entries(data)

    if not broken:
        print("No invalid systemd-boot entries found.")
        return

    mode = "APPLY" if args.apply else "DRY-RUN"
    print(f"Invalid systemd-boot entries detected ({mode}):\n")

    for e in broken:
        print(f" Boot{e['id']}  {e['guid']}  {e['path']}")
        if args.apply:
            delete_entry(e["id"])

    if not args.apply:
        print("\nDry-run: no changes made. Use --apply to perform removal.")
    else:
        print("\nDone.")


if __name__ == "__main__":
    main()
