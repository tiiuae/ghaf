#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
import argparse
import hashlib
import json
import os

parser = argparse.ArgumentParser(
    description="Rename verity artifacts and generate manifest."
)
parser.add_argument(
    "--version", required=True, help="Version string for @v placeholder."
)
parser.add_argument(
    "--system", required=True, help="System identifier (e.g. x86_64-linux)."
)
parser.add_argument(
    "--hash-file", required=True, help="Path to dm-verity root hash file."
)
parser.add_argument(
    "--root-image", required=True, help="Path to compressed root image."
)
parser.add_argument(
    "--verity-image", required=True, help="Path to compressed verity image."
)
parser.add_argument("--kernel-image", required=True, help="Path to kernel/UKI image.")
parser.add_argument("--manifest", required=True, help="Output manifest path template.")
parser.add_argument(
    "--root-unpacked-size",
    type=int,
    required=True,
    help="Uncompressed root image size in bytes.",
)
parser.add_argument(
    "--verity-unpacked-size",
    type=int,
    required=True,
    help="Uncompressed verity image size in bytes.",
)


def fixname(filename: str, version: str, fragment: str) -> str:
    filename = filename.replace("@v", version)
    filename = filename.replace("@u", fragment)
    return filename


def rename(filename: str, version: str, fragment: str) -> str:
    new = fixname(filename, version, fragment)
    os.rename(filename, new)
    print(f"{filename} -> {new}")
    return new


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def file_size(path: str) -> int:
    return os.path.getsize(path)


def main() -> None:
    args = parser.parse_args()

    with open(args.hash_file, "r", encoding="utf-8") as f:
        first_line = f.readline().strip()
    if not first_line:
        raise ValueError("hash_file first line is empty")

    root_verity_hash = first_line.split()[0]
    if len(root_verity_hash) < 64 or any(
        c not in "0123456789abcdefABCDEF" for c in root_verity_hash[:64]
    ):
        raise ValueError(
            "hash_file must contain at least 64 hex characters in first line"
        )
    root_verity_hash = root_verity_hash[:64]

    storehash = root_verity_hash[:16]

    store = rename(args.root_image, args.version, storehash)
    verity = rename(args.verity_image, args.version, storehash)
    kernel = rename(args.kernel_image, args.version, storehash)

    manifest = {
        "manifest_version": 0,
        "system": args.system,
        "meta": {},  # FIXME: reserved for future, just arbitrary metadata
        "version": args.version,
        "root_verity_hash": root_verity_hash,
        "root": {
            "file": os.path.basename(store),
            "sha256": sha256_file(store),
            "packed_size": file_size(store),
            "unpacked_size": args.root_unpacked_size,
        },
        "verity": {
            "file": os.path.basename(verity),
            "sha256": sha256_file(verity),
            "packed_size": file_size(verity),
            "unpacked_size": args.verity_unpacked_size,
        },
        "kernel": {
            "file": os.path.basename(kernel),
            "sha256": sha256_file(kernel),
            "unpacked_size": file_size(kernel),
        },
    }
    with open(
        fixname(args.manifest, args.version, storehash), "w", encoding="utf-8"
    ) as file:
        json.dump(manifest, file, indent=2, sort_keys=True)
        file.write("\n")


if __name__ == "__main__":
    main()
