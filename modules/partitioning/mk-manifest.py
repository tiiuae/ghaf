#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
import argparse
import hashlib
import json
import os
import shutil
import subprocess

parser = argparse.ArgumentParser(description="Generate or sign Ghaf update artifacts.")
parser.add_argument("--version", help="Version string for @v placeholder.")
parser.add_argument("--system", help="System identifier (e.g. x86_64-linux).")
parser.add_argument("--target", help="Exact hardware/update target identifier.")
parser.add_argument(
    "--build-system",
    help="System identifier for the build platform that produced the artifacts.",
)
parser.add_argument("--generation", type=int, help="Monotonic generation.")
parser.add_argument("--hash-file", help="Path to dm-verity root hash file.")
parser.add_argument("--root-image", help="Path to compressed root image.")
parser.add_argument("--verity-image", help="Path to compressed verity image.")
parser.add_argument("--kernel-image", help="Path to kernel/UKI image.")
parser.add_argument("--manifest", help="Output manifest path template.")
parser.add_argument(
    "--input-manifest",
    help="Existing manifest to sign and copy instead of generating one.",
)
parser.add_argument(
    "--key-dir", help="Directory containing db.key, db.crt, and update.key."
)
parser.add_argument(
    "--output", help="Directory for signed artifacts and manifest copies."
)
parser.add_argument(
    "--root-unpacked-size",
    type=int,
    help="Uncompressed root image size in bytes.",
)
parser.add_argument(
    "--verity-unpacked-size",
    type=int,
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


def load_manifest(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        manifest = json.load(f)
    if not isinstance(manifest, dict):
        raise TypeError("manifest must be a JSON object")
    return manifest


def validate_manifest(manifest: dict) -> None:
    if manifest.get("manifest_version") != 2:
        raise ValueError("manifest_version must be 2")

    target = manifest.get("target")
    if not isinstance(target, str) or not target:
        raise ValueError("target must be a non-empty string")

    system = manifest.get("system")
    if not isinstance(system, str) or not system:
        raise ValueError("system must be a non-empty string")

    build_system = manifest.get("build-system")
    if not isinstance(build_system, str) or not build_system:
        raise ValueError("build-system must be a non-empty string")

    generation = manifest.get("generation")
    if not isinstance(generation, int) or generation <= 0:
        raise ValueError("generation must be a positive integer")

    root_verity_hash = manifest.get("root_verity_hash")
    if not isinstance(root_verity_hash, str) or len(root_verity_hash) != 64:
        raise ValueError("root_verity_hash must be a 64-character hex string")
    if any(c not in "0123456789abcdefABCDEF" for c in root_verity_hash):
        raise ValueError("root_verity_hash must be a 64-character hex string")


def require_key_dir(key_dir: str) -> None:
    for required in ("db.key", "db.crt", "update.key"):
        path = os.path.join(key_dir, required)
        if not os.path.isfile(path) or os.path.getsize(path) == 0:
            raise FileNotFoundError(f"Missing {path}")


def update_manifest_file(manifest: dict, path: str) -> None:
    with open(path, "w", encoding="utf-8") as file:
        json.dump(manifest, file, indent=2, sort_keys=True)
        file.write("\n")


def copy_artifact(source_dir: str, output_dir: str, filename: str) -> str:
    if filename != os.path.basename(filename):
        raise ValueError(f"Unsafe artifact path: {filename}")

    source = os.path.join(source_dir, filename)
    destination = os.path.join(output_dir, filename)
    shutil.copy2(source, destination)
    return destination


def sign_output(manifest_path: str, key_dir: str, output_dir: str) -> None:
    require_key_dir(key_dir)
    os.makedirs(output_dir, exist_ok=True)

    source_dir = os.path.dirname(os.path.abspath(manifest_path))
    manifest = load_manifest(manifest_path)
    validate_manifest(manifest)

    output_manifest = os.path.join(output_dir, os.path.basename(manifest_path))
    shutil.copy2(manifest_path, output_manifest)

    for kind in ("root", "verity"):
        artifact = manifest[kind]["file"]
        copied = copy_artifact(source_dir, output_dir, artifact)
        manifest[kind]["sha256"] = sha256_file(copied)
        manifest[kind]["packed_size"] = file_size(copied)

    kernel = manifest["kernel"]["file"]
    if kernel != os.path.basename(kernel):
        raise ValueError(f"Unsafe artifact path: {kernel}")

    source_kernel = os.path.join(source_dir, kernel)
    signed_kernel = os.path.join(output_dir, kernel)
    subprocess.run(
        [
            "sbsign",
            "--key",
            os.path.join(key_dir, "db.key"),
            "--cert",
            os.path.join(key_dir, "db.crt"),
            "--output",
            signed_kernel,
            source_kernel,
        ],
        check=True,
    )

    manifest["kernel"]["sha256"] = sha256_file(signed_kernel)
    signed_size = file_size(signed_kernel)
    manifest["kernel"]["packed_size"] = signed_size
    manifest["kernel"]["unpacked_size"] = signed_size

    update_manifest_file(manifest, output_manifest)
    subprocess.run(
        [
            "openssl",
            "pkeyutl",
            "-sign",
            "-rawin",
            "-inkey",
            os.path.join(key_dir, "update.key"),
            "-in",
            output_manifest,
            "-out",
            f"{output_manifest}.sig",
        ],
        check=True,
    )
    if file_size(f"{output_manifest}.sig") != 64:
        raise ValueError("manifest signature must be 64 bytes")


def main() -> None:
    args = parser.parse_args()

    if args.input_manifest:
        build_args = [
            args.version,
            args.system,
            args.target,
            args.build_system,
            args.generation,
            args.hash_file,
            args.root_image,
            args.verity_image,
            args.kernel_image,
            args.manifest,
            args.root_unpacked_size,
            args.verity_unpacked_size,
        ]
        if any(value is not None for value in build_args):
            raise ValueError(
                "--input-manifest conflicts with artifact generation arguments"
            )
        if not args.key_dir or not args.output:
            raise ValueError("--input-manifest requires --key-dir and --output")
        sign_output(args.input_manifest, args.key_dir, args.output)
        print(f"Signed update written to {args.output}")
        return

    if bool(args.key_dir) != bool(args.output):
        raise ValueError("--key-dir and --output must be used together")

    required = {
        "--version": args.version,
        "--system": args.system,
        "--target": args.target,
        "--build-system": args.build_system,
        "--generation": args.generation,
        "--hash-file": args.hash_file,
        "--root-image": args.root_image,
        "--verity-image": args.verity_image,
        "--kernel-image": args.kernel_image,
        "--manifest": args.manifest,
        "--root-unpacked-size": args.root_unpacked_size,
        "--verity-unpacked-size": args.verity_unpacked_size,
    }
    missing = [name for name, value in required.items() if value is None]
    if missing:
        raise ValueError(f"missing required arguments: {', '.join(missing)}")

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
        "manifest_version": 2,
        "system": args.system,
        "target": args.target,
        "build-system": args.build_system,
        "generation": args.generation,
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
            "packed_size": file_size(kernel),
            "unpacked_size": file_size(kernel),
        },
    }

    manifest_path = fixname(args.manifest, args.version, storehash)
    update_manifest_file(manifest, manifest_path)

    if args.key_dir and args.output:
        sign_output(manifest_path, args.key_dir, args.output)
        print(f"Signed update written to {args.output}")


if __name__ == "__main__":
    main()
