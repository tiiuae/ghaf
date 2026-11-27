# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  name,
  flasher,
  launcher,
}:
let
  runtimeRoots = [
    flasher
    pkgs.bash
    pkgs.coreutils
    pkgs.util-linux
  ];
  closureInfo = pkgs.closureInfo { rootPaths = runtimeRoots; };
in
pkgs.runCommand name
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gzip
      pkgs.gnutar
    ];
    # Make the complete closure available in the sandbox while the bundle is assembled.
    buildInputs = runtimeRoots;
  }
  ''
    set -euo pipefail

    runtime="$TMPDIR/runtime"
    mkdir -p "$runtime/nix/store" "$out"

    while IFS= read -r store_path; do
      test -e "$store_path"
      cp -a -- "$store_path" "$runtime/nix/store/"
    done < ${closureInfo}/store-paths

    printf '%s' "/nix/store/$(basename ${flasher})/bin/flash-ghaf-host" > "$runtime/.flash-bin-path"
    install -m 755 ${launcher} "$runtime/launcher.sh"

    # Keep the archive reproducible so identical flasher closures produce identical artifacts.
    tar --sort=name --mtime='@1' --owner=0 --group=0 --numeric-owner \
      -C "$runtime" -cf - . | gzip -n > "$out/flash-runtime.tar.gz"
    install -m 755 ${launcher} "$out/launcher.sh"
  ''
