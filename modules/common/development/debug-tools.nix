# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.ghaf.development.debug.tools;
in
  with lib; {
    options.ghaf.development.debug.tools = {
      enable = mkEnableOption "Debug Tools";
    };

    config = mkIf cfg.enable {
      environment.systemPackages = with pkgs;
        [
          # For lspci:
          pciutils

          # For lsusb:
          usbutils

          # Useful in NetVM
          ethtool

          # Basic monitors
          htop
          iftop
          iotop

          traceroute
          dig
          evtest

          # Performance testing
          speedtest-cli
          iperf

          # Let's have this fixed version according to kernel.
          # It would be possible to select also latest producing currently (12-3-2024) perf version 6.6.7
          # linuxPackages_latest.perf
          linuxKernel.packages.linux_6_1.perf
        ]
        # TODO Can this be changed to platformPkgs to filter ?
        # LuaJIT (which is sysbench dependency) not available on RISC-V
        ++ lib.lists.optionals (config.nixpkgs.hostPlatform.system != "riscv64-linux") [sysbench]
        # runtimeShell (unixbench dependency) not available on RISC-V nor on cross-compiled Orin AGX/NX
        ++ lib.lists.optionals (stdenv.hostPlatform == stdenv.buildPlatform) [unixbench];
    };
  }
