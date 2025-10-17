# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let

  buildKernel = import ../kernel-config-builder.nix { inherit config pkgs lib; };
  config_baseline = ./configs/ghaf_guest_hardened_baseline-x86;
  guest_hardened_kernel = buildKernel {
    inherit config_baseline;
    host_build = false;
  };

  cfg = config.ghaf.guest.kernel.hardening;
in
{
  options.ghaf.guest.kernel.hardening = {
    enable = lib.mkOption {
      description = "Enable Ghaf Guest hardening feature";
      type = lib.types.bool;
      default = false;
    };

    graphics.enable = lib.mkOption {
      description = "Enable support for Graphics in the Ghaf Guest";
      type = lib.types.bool;
      default = false;
    };
  };

  config = lib.mkIf pkgs.stdenv.hostPlatform.isx86_64 {
    boot.kernelPackages =
      if cfg.enable then pkgs.linuxPackagesFor guest_hardened_kernel else pkgs.linuxPackages_latest;
  };
}
