# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
{
  imports = [
    ./microvm-crosvm-store-disk-overlay.nix
    ./microvm-crosvm-vfio-options.nix
  ];

  options.microvm.extraBuildCommands = lib.mkOption {
    type = lib.types.nullOr lib.types.lines;
    default = null;
    description = "Shell commands to run at the end of microvm derivation build.";
  };

  config.microvm.declaredRunner = lib.mkIf (config.microvm.extraBuildCommands != null) (
    config.microvm.runner.${config.microvm.hypervisor}.overrideAttrs (oldAttrs: {
      buildCommand =
        oldAttrs.buildCommand
        # `microvm-run` is initially a symlink to another store path that we can't write to,
        # so first we recreate it in the current build directory
        + ''
          cp --remove-destination $(readlink "$out/bin/microvm-run") "$out/bin/microvm-run"
        ''
        + config.microvm.extraBuildCommands;
    })
  );
}
