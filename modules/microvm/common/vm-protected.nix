# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
{
  _file = ./pkvm-guest.nix;

  options.ghaf.virtualization.microvm.protected-vm = {
    enable = lib.mkEnableOption "this guest to be run as a protected VM under the pKVM hypervisor.";
  };

  config = lib.mkIf config.ghaf.virtualization.microvm.protected-vm.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isAarch64;
        message = "ghaf.virtualization.microvm.protected-vm expects ARM64 platform; got ${pkgs.stdenv.hostPlatform.system}.";
      }
    ];

    microvm.crosvm.extraArgs = [
      "--protected-vm-without-firmware"
      "--unmap-guest-memory-on-fork"
      "--disable-sandbox"
      "--smccc-trng"
    ];
  };
}
