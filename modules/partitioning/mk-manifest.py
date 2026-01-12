#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
import sys
import json
import os


def fixname(filename, version, fragment):
    filename = filename.replace("@v", version)
    filename = filename.replace("@u", fragment)
    return filename


def rename(filename, version, fragment):
    new = fixname(filename, version, fragment)
    os.rename(filename, new)
    print(f"{filename} -> {new}")
    return new


def main():
    if len(sys.argv) != 7:
        print(
            f"Usage: {sys.argv[0]} version hash_file rootimage verityimage kernel manifest"
        )
        sys.exit(1)

    version, hash_file, store, verity, kernel, manifest_file = sys.argv[1:]

    with open(hash_file, "r") as f:
        root_verity_hash = f.readline().strip()

    if len(root_verity_hash) < 64:
        raise ValueError(
            "hash_file must contain at least 64 hex characters in first line"
        )

    storehash = root_verity_hash[:16]

    store = rename(store, version, storehash)
    verity = rename(verity, version, storehash)
    kernel = rename(kernel, version, storehash)

    manifest = {
        "meta": {},  # FIXME: reserved for future, just arbitrary metadata
        "version": version,
        "root_verity_hash": root_verity_hash,
        "root": {
            "file": os.path.basename(store),
            "sha256": "fixme",
        },
        "verity": {
            "file": os.path.basename(verity),
            "sha256": "fixme",
        },
        "kernel": {
            "file": os.path.basename(kernel),
            "sha256": "fixme",
        },
    }
    manifest = json.dumps(manifest, indent=True)
    with open(fixname(manifest_file, version, storehash), "w") as file:
        file.write(manifest)


if __name__ == "__main__":
    main()
