# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Thin NixOS module exposing the Ghaf-patched QEMU package.
# The package itself lives in packages/pkgs-by-name/ghaf-qemu/package.nix
# and can be built standalone: nix build .#ghaf-qemu
#
{
  lib,
  pkgs,
  ...
}:
{
  options.ghaf.virtualization.qemu = {
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.ghaf-qemu;
      defaultText = lib.literalExpression "pkgs.ghaf-qemu";
      description = "The QEMU package used across Ghaf modules.";
    };
  };
}
