# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Shared ESP utilities for Jetson Orin targets.
#
# Exposes mk-esp-contents (type-checked Python script for populating ESP with
# systemd-boot + Type 1 BLS entries) and the device tree path as reusable
# system.build attributes, avoiding duplication between sdimage.nix and
# verity-image.nix.
{
  config,
  pkgs,
  ...
}:
let
  mkESPContentSource = pkgs.replaceVars ./mk-esp-contents.py {
    inherit (pkgs.buildPackages) python3;
  };
in
{
  _file = ./esp-utils.nix;

  config.system.build = {
    # Type-checked mk-esp-contents script
    mkESPContent =
      pkgs.runCommand "mk-esp-contents"
        {
          nativeBuildInputs = with pkgs; [
            mypy
            python3
          ];
        }
        ''
          install -m755 ${mkESPContentSource} $out
          mypy \
            --no-implicit-optional \
            --disallow-untyped-calls \
            --disallow-untyped-defs \
            $out
        '';

    # Resolved path to the device tree blob for this board
    fdtPath = "${config.hardware.deviceTree.package}/${config.hardware.deviceTree.name}";
  };
}
