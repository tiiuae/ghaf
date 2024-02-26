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
          perf-tools
          linuxPackages.perf

        ]
        ++
        # LuaJIT (which is sysbench dependency) not available on RISC-V
        # TODO Can this be changed to platformPkgs to filter ?
        lib.optional (config.nixpkgs.hostPlatform.system != "riscv64-linux") sysbench;
    };
  }
