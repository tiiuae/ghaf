#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
import argparse
import hashlib
import json
import os
import sys
import tempfile


def add_generate_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--version", required=True, help="Version string for @v placeholder."
    )
    parser.add_argument(
        "--system",
        required=True,
        help="Nix target system identifier (for example aarch64-linux).",
    )
    parser.add_argument(
        "--build-system",
        required=True,
        help="Nix build system identifier that produced the artifacts.",
    )
    parser.add_argument(
        "--target", required=True, help="Exact hardware/update target identifier."
    )
    parser.add_argument(
        "--generation", required=True, type=int, help="Monotonic generation."
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
    parser.add_argument(
        "--kernel-image", required=True, help="Path to kernel/UKI image."
    )
    parser.add_argument(
        "--manifest", required=True, help="Output manifest path template."
    )
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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate and rehash Ghaf update manifests."
    )
    commands = parser.add_subparsers(dest="command", required=True)
    add_generate_arguments(commands.add_parser("generate"))
    rehash = commands.add_parser(
        "rehash", help="Recompute artifact hashes and packed sizes in a manifest."
    )
    rehash.add_argument(
        "--manifest", required=True, help="Manifest to update atomically."
    )

    # Keep direct option invocation compatible with the original generator CLI.
    argv = sys.argv[1:]
    if argv and argv[0].startswith("-"):
        argv.insert(0, "generate")
    return parser.parse_args(argv)


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
    digest = hashlib.sha256()
    with open(path, "rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def file_size(path: str) -> int:
    return os.path.getsize(path)


def validate_metadata(manifest: dict) -> None:
    if manifest.get("manifest_version") != 2:
        raise ValueError("manifest_version must be 2")
    for field in ("system", "target", "version"):
        if not isinstance(manifest.get(field), str) or not manifest[field].strip():
            raise ValueError(f"manifest {field} must be a non-empty string")
    build_system = manifest.get("build-system")
    if build_system is not None and (
        not isinstance(build_system, str) or not build_system.strip()
    ):
        raise ValueError("manifest build-system must be a non-empty string")
    generation = manifest.get("generation")
    if (
        isinstance(generation, bool)
        or not isinstance(generation, int)
        or generation <= 0
    ):
        raise ValueError("manifest generation must be a positive integer")
    root_hash = manifest.get("root_verity_hash")
    if (
        not isinstance(root_hash, str)
        or len(root_hash) != 64
        or any(character not in "0123456789abcdefABCDEF" for character in root_hash)
    ):
        raise ValueError("root_verity_hash must be exactly 64 hexadecimal characters")


def artifact_path(manifest_path: str, manifest: dict, kind: str) -> str:
    entry = manifest.get(kind)
    if not isinstance(entry, dict):
        raise TypeError(f"manifest {kind} entry must be an object")
    name = entry.get("file")
    if (
        not isinstance(name, str)
        or not name
        or name != os.path.basename(name)
        or name in (".", "..")
    ):
        raise ValueError(f"manifest {kind} file must be a safe basename")
    return os.path.join(os.path.dirname(os.path.abspath(manifest_path)), name)


def write_manifest(path: str, manifest: dict) -> None:
    directory = os.path.dirname(os.path.abspath(path))
    descriptor, temporary = tempfile.mkstemp(
        prefix=f".{os.path.basename(path)}.", dir=directory, text=True
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as file:
            json.dump(manifest, file, indent=2, sort_keys=True)
            file.write("\n")
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def generate(args: argparse.Namespace) -> None:
    with open(args.hash_file, "r", encoding="utf-8") as file:
        first_line = file.readline().strip()
    if not first_line:
        raise ValueError("hash_file first line is empty")

    root_verity_hash = first_line.split()[0]
    if len(root_verity_hash) < 64 or any(
        character not in "0123456789abcdefABCDEF" for character in root_verity_hash[:64]
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
        "manifest_version": 2,
        "system": args.system,
        "build-system": args.build_system,
        "target": args.target,
        "generation": args.generation,
        "meta": {},
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
            "packed_size": file_size(kernel),
            "unpacked_size": file_size(kernel),
        },
    }
    validate_metadata(manifest)
    write_manifest(fixname(args.manifest, args.version, storehash), manifest)


def rehash(manifest_path: str) -> None:
    with open(manifest_path, "r", encoding="utf-8") as file:
        manifest = json.load(file)
    validate_metadata(manifest)

    for kind in ("root", "verity", "kernel"):
        path = artifact_path(manifest_path, manifest, kind)
        size = file_size(path)
        manifest[kind]["sha256"] = sha256_file(path)
        manifest[kind]["packed_size"] = size
        if kind == "kernel":
            manifest[kind]["unpacked_size"] = size
        else:
            unpacked_size = manifest[kind].get("unpacked_size")
            if (
                isinstance(unpacked_size, bool)
                or not isinstance(unpacked_size, int)
                or unpacked_size <= 0
            ):
                raise ValueError(f"manifest {kind} unpacked_size must be positive")

    write_manifest(manifest_path, manifest)


def main() -> None:
    args = parse_args()
    if args.command == "generate":
        generate(args)
    else:
        rehash(args.manifest)


if __name__ == "__main__":
    main()
