#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
"""Examples:

  Build manifest and rename artifacts:
    ghaf-mk-manifest build --version 1.0 --system x86_64-linux \
      --hash-file dm-verity-root-hash --root-image root.raw.zst \
      --verity-image verity.raw.zst --kernel-image kernel.efi \
      --manifest out/system_@v_@u.manifest \
      --root-unpacked-size 123 --verity-unpacked-size 456

  Sign kernel, link root/verity, write output to a new directory:
    ghaf-mk-manifest sign -o signed out/system_1.0_deadbeef.manifest -- \
      --private-key key.pem --certificate cert.pem

  Recompute kernel hash/size in-place:
    ghaf-mk-manifest rehash out/system_1.0_deadbeef.manifest
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import sys
from pathlib import Path
from typing import Any, cast

parser = argparse.ArgumentParser(description="Manage verity manifest artifacts.")
subparsers = parser.add_subparsers(dest="command", required=True)

build_parser = subparsers.add_parser(
    "build", help="Rename artifacts and generate manifest."
)
build_parser.add_argument(
    "--version", required=True, help="Version string for @v placeholder."
)
build_parser.add_argument(
    "--system", required=True, help="System identifier (e.g. x86_64-linux)."
)
build_parser.add_argument(
    "--hash-file", required=True, help="Path to dm-verity root hash file."
)
build_parser.add_argument(
    "--root-image", required=True, help="Path to compressed root image."
)
build_parser.add_argument(
    "--verity-image", required=True, help="Path to compressed verity image."
)
build_parser.add_argument(
    "--kernel-image", required=True, help="Path to kernel/UKI image."
)
build_parser.add_argument(
    "--manifest", required=True, help="Output manifest path template."
)
build_parser.add_argument(
    "--root-unpacked-size",
    type=int,
    required=True,
    help="Uncompressed root image size in bytes.",
)
build_parser.add_argument(
    "--verity-unpacked-size",
    type=int,
    required=True,
    help="Uncompressed verity image size in bytes.",
)

sign_parser = subparsers.add_parser(
    "sign", help="Sign kernel and write updated manifest/artifacts to output directory."
)
sign_parser.add_argument("-o", "--output", required=True, help="Output directory.")
sign_parser.add_argument(
    "--copy", action="store_true", help="Copy root/verity instead of symlinks."
)
sign_parser.add_argument("--systemd-sbsign", help="Path to systemd-sbsign binary.")
sign_parser.add_argument("manifest", help="Input .manifest file.")
sign_parser.add_argument(
    "sbsign_args",
    nargs=argparse.REMAINDER,
    help="Arguments passed to systemd-sbsign after '--'.",
)

rehash_parser = subparsers.add_parser(
    "rehash", help="Recompute kernel hash/size and update manifest in-place."
)
rehash_parser.add_argument("manifest", help="Input .manifest file to update.")


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


def load_manifest(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return cast(dict[str, Any], json.load(f))


def save_manifest_atomic(path: Path, manifest: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=path.parent, delete=False
    ) as tmp:
        json.dump(manifest, tmp, indent=2, sort_keys=True)
        tmp.write("\n")
        tmp_name = tmp.name
    os.replace(tmp_name, path)


def parse_root_hash(path: str) -> str:
    with open(path, "r", encoding="utf-8") as f:
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
    return root_verity_hash[:64]


def resolve_artifact_path(manifest_path: Path, rel_name: str) -> Path:
    return manifest_path.parent / rel_name


def cmd_build(args: argparse.Namespace) -> None:
    root_verity_hash = parse_root_hash(args.hash_file)

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
    save_manifest_atomic(
        Path(fixname(args.manifest, args.version, storehash)), manifest
    )


def link_or_add_indirect_gcroot(src: Path, dst: Path) -> None:
    if dst.exists() or dst.is_symlink():
        dst.unlink()
    if str(src).startswith("/nix/store/"):
        src_resolved = src.resolve()
        store_root = Path(*src_resolved.parts[:4])
        gcroot = dst.parent / f".{dst.name}.gcroot"
        if gcroot.exists() or gcroot.is_symlink():
            gcroot.unlink()
        subprocess.run(
            ["nix-store", "--realise", "--add-root", str(gcroot), str(store_root)],
            check=True,
        )
        dst.symlink_to(src_resolved)
    else:
        dst.symlink_to(src)


def cmd_sign(args: argparse.Namespace) -> None:
    manifest_path = Path(args.manifest).resolve()
    manifest = load_manifest(manifest_path)

    outdir = Path(args.output).resolve()
    outdir.mkdir(parents=True, exist_ok=True)

    root_file = manifest.get("root", {}).get("file")
    verity_file = manifest.get("verity", {}).get("file")
    kernel_file = manifest.get("kernel", {}).get("file")
    if not root_file or not verity_file or not kernel_file:
        raise ValueError("manifest must contain root.file, verity.file and kernel.file")

    src_root = resolve_artifact_path(manifest_path, root_file)
    src_verity = resolve_artifact_path(manifest_path, verity_file)
    src_kernel = resolve_artifact_path(manifest_path, kernel_file)
    for path in (src_root, src_verity, src_kernel):
        if not path.is_file():
            raise FileNotFoundError(f"artifact not found: {path}")

    dst_root = outdir / src_root.name
    dst_verity = outdir / src_verity.name
    dst_kernel = outdir / src_kernel.name

    if args.copy:
        if dst_root.exists() or dst_root.is_symlink():
            dst_root.unlink()
        if dst_verity.exists() or dst_verity.is_symlink():
            dst_verity.unlink()
        shutil.copy2(src_root, dst_root)
        shutil.copy2(src_verity, dst_verity)
    else:
        link_or_add_indirect_gcroot(src_root, dst_root)
        link_or_add_indirect_gcroot(src_verity, dst_verity)

    with tempfile.NamedTemporaryFile(
        mode="wb",
        dir=outdir,
        prefix=f".{dst_kernel.name}.",
        suffix=".tmp",
    ) as tmp:
        tmp_kernel_path = Path(tmp.name)
        shutil.copy2(src_kernel, tmp_kernel_path)
        signer = args.systemd_sbsign if args.systemd_sbsign else "systemd-sbsign"
        cmd = [
            signer,
            *args.sbsign_args,
            "--output",
            str(dst_kernel),
            str(tmp_kernel_path),
        ]
        subprocess.run(cmd, check=True)

    manifest["kernel"]["sha256"] = sha256_file(str(dst_kernel))
    manifest["kernel"]["unpacked_size"] = file_size(str(dst_kernel))
    save_manifest_atomic(outdir / manifest_path.name, manifest)


def cmd_rehash(args: argparse.Namespace) -> None:
    manifest_path = Path(args.manifest).resolve()
    manifest = load_manifest(manifest_path)
    kernel_file = manifest.get("kernel", {}).get("file")
    if not kernel_file:
        raise ValueError("manifest.kernel.file is missing or empty")
    kernel_path = resolve_artifact_path(manifest_path, kernel_file)
    if not kernel_path.is_file():
        raise FileNotFoundError(f"kernel image not found: {kernel_path}")
    manifest["kernel"]["sha256"] = sha256_file(str(kernel_path))
    manifest["kernel"]["unpacked_size"] = file_size(str(kernel_path))
    save_manifest_atomic(manifest_path, manifest)


def main() -> None:
    if len(sys.argv) == 1:
        parser.print_help()
        return
    args = parser.parse_args()
    if getattr(args, "sbsign_args", None) and args.sbsign_args[0] == "--":
        args.sbsign_args = args.sbsign_args[1:]
    if args.command == "build":
        cmd_build(args)
    elif args.command == "sign":
        cmd_sign(args)
    elif args.command == "rehash":
        cmd_rehash(args)
    else:
        raise ValueError(f"unknown command: {args.command}")


if __name__ == "__main__":
    main()
