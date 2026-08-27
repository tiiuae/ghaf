# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Thin NixOS module exposing the Ghaf-patched QEMU package from ghafpkgs.
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
      default = if pkgs.stdenv.hostPlatform.isx86_64 then pkgs.ghaf-x86-qemu else pkgs.ghaf-nvidia-qemu;
      defaultText = lib.literalExpression ''
        if pkgs.stdenv.hostPlatform.isx86_64 then pkgs.ghaf-x86-qemu else pkgs.ghaf-nvidia-qemu
      '';
      description = "The QEMU package used across Ghaf modules.";
    };
  };
}
