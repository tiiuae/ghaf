# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  needsStoreDiskFix = config.microvm.hypervisor == "crosvm" && config.microvm.storeOnDisk;
  storeDisk = toString config.microvm.storeDisk;
in
{
  # TODO: Remove after https://github.com/microvm-nix/microvm.nix/pull/584
  # is merged and the microvm input is updated. Crosvm's -r option both
  # attaches a disk and injects root=/dev/vda, so the Nix store image must be
  # attached as a normal read-only block device instead.
  microvm.declaredRunner = lib.mkIf needsStoreDiskFix (
    config.microvm.runner.crosvm.overrideAttrs (oldAttrs: {
      buildCommand = oldAttrs.buildCommand + ''
        runner="$out/bin/microvm-run"
        cp --dereference "$runner" "$runner.fixed"
        rm "$runner"
        mv "$runner.fixed" "$runner"
        chmod +x "$runner"
        if grep -Fq -- "-r ${storeDisk}" "$runner"; then
          substituteInPlace "$runner" \
            --replace-fail "-r ${storeDisk}" "--block ${storeDisk},ro=true"
        elif ! grep -Fq -- "${storeDisk},ro=true" "$runner"; then
          echo "Crosvm runner does not contain the expected store-disk argument" >&2
          exit 1
        fi
      '';
    })
  );
}
