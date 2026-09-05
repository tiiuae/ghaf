# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
import argparse
import hashlib
import json
import os
import sys
import tempfile


def add_generate_arguments(parser: argparse.ArgumentParser) -> None:
    for name, help_text in (
        ("version", "Version string for @v placeholder."),
        ("system", "Nix target system identifier (for example aarch64-linux)."),
        ("build-system", "Nix build system identifier that produced the artifacts."),
        ("target", "Exact hardware/update target identifier."),
        ("hash-file", "Path to dm-verity root hash file."),
        ("root-image", "Path to compressed root image."),
        ("verity-image", "Path to compressed verity image."),
        ("kernel-image", "Path to kernel/UKI image."),
        ("manifest", "Output manifest path template."),
    ):
        parser.add_argument(f"--{name}", required=True, help=help_text)
    for name, help_text in (
        ("generation", "Monotonic generation."),
        ("root-unpacked-size", "Uncompressed root image size in bytes."),
        ("verity-unpacked-size", "Uncompressed verity image size in bytes."),
    ):
        parser.add_argument(f"--{name}", type=int, required=True, help=help_text)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate and rehash Ghaf update manifests."
    )
    commands = parser.add_subparsers(dest="command", required=True)
    add_generate_arguments(commands.add_parser("generate"))
    for command, help_text in (
        ("validate", "Check metadata, artifact names, and sizes before signing."),
        ("rehash", "Recompute artifact hashes and packed sizes atomically."),
    ):
        subparser = commands.add_parser(command, help=help_text)
        subparser.add_argument("--manifest", required=True, help="Manifest path.")

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


def validate_metadata(manifest: dict) -> None:
    if manifest.get("manifest_version") != 2:
        raise ValueError("manifest_version must be 2")
    for field in ("system", "target", "version"):
        if not isinstance(manifest.get(field), str) or not manifest[field].strip():
            raise ValueError(f"manifest {field} must be a non-empty string")
    build_system = manifest.get("build-system")
    if "build-system" in manifest and (
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


def validate_manifest(path: str, manifest: dict) -> None:
    validate_metadata(manifest)
    names = [os.path.basename(path), os.path.basename(path) + ".sig"]
    for kind in ("root", "verity", "kernel"):
        names.append(os.path.basename(artifact_path(path, manifest, kind)))
    if len(names) != len(set(names)):
        raise ValueError("Artifact file names must be distinct from release metadata")
    for kind in ("root", "verity"):
        size = manifest[kind].get("unpacked_size")
        if isinstance(size, bool) or not isinstance(size, int) or size <= 0:
            raise ValueError(f"manifest {kind} unpacked_size must be positive")


def rehash_artifacts(path: str, manifest: dict) -> None:
    validate_manifest(path, manifest)
    for kind in ("root", "verity", "kernel"):
        update_artifact(manifest, kind, artifact_path(path, manifest, kind))


def update_artifact(manifest: dict, kind: str, path: str) -> None:
    size = os.path.getsize(path)
    manifest[kind].update(sha256=sha256_file(path), packed_size=size)
    if kind == "kernel":
        manifest[kind]["unpacked_size"] = size


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

    manifest = {
        "manifest_version": 2,
        "system": args.system,
        "build-system": args.build_system,
        "target": args.target,
        "generation": args.generation,
        "meta": {},
        "version": args.version,
        "root_verity_hash": root_verity_hash,
    }
    for kind in ("root", "verity", "kernel"):
        filename = rename(getattr(args, f"{kind}_image"), args.version, storehash)
        manifest[kind] = {"file": os.path.basename(filename)}
        if kind != "kernel":
            manifest[kind]["unpacked_size"] = getattr(args, f"{kind}_unpacked_size")
        update_artifact(manifest, kind, filename)
    path = fixname(args.manifest, args.version, storehash)
    validate_manifest(path, manifest)
    write_manifest(path, manifest)


def main() -> None:
    args = parse_args()
    if args.command == "generate":
        generate(args)
    else:
        with open(args.manifest, "r", encoding="utf-8") as file:
            manifest = json.load(file)
        if args.command == "validate":
            validate_manifest(args.manifest, manifest)
        else:
            rehash_artifacts(args.manifest, manifest)
            write_manifest(args.manifest, manifest)


if __name__ == "__main__":
    main()
