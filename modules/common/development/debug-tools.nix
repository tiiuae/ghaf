# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.ghaf.development.debug.tools;

  rm-linux-bootmgrs = pkgs.callPackage ./scripts/rm_linux_bootmgr_entries.nix {};
  perf-test-script = pkgs.callPackage ./scripts/perf_test_icicle_kit.nix {};
  sysbench-test-script = pkgs.callPackage ./scripts/sysbench_test.nix {};
  sysbench-fileio-test-script = pkgs.callPackage ./scripts/sysbench_fileio_test.nix {};
  nvpmodel-check = pkgs.callPackage ./scripts/nvpmodel_check.nix {};

  inherit (lib) mkEnableOption mkIf;
in {
  options.ghaf.development.debug.tools = {
    enable = mkEnableOption "Debug Tools";
  };

  config = mkIf cfg.enable {
    environment.etc = {
      audio_test.source = ./audio_test;
    };
    environment.systemPackages =
      builtins.attrValues {
        inherit
          (pkgs)
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
          # For deleting Linux Boot Manager entries in automated testing
          
          efibootmgr
          # Performance testing
          
          speedtest-cli
          iperf
          ;
      }
      ++
      # Match perf version with kernel.
      [
        config.boot.kernelPackages.perf
        perf-test-script
        sysbench-test-script
        sysbench-fileio-test-script
        nvpmodel-check
        rm-linux-bootmgrs
      ]
      # TODO Can this be changed to platformPkgs to filter ?
      # LuaJIT (which is sysbench dependency) not available on RISC-V
      ++ lib.optional (config.nixpkgs.hostPlatform.system != "riscv64-linux") pkgs.sysbench
      # runtimeShell (unixbench dependency) not available on RISC-V nor on cross-compiled Orin AGX/NX
      ++ lib.optional (pkgs.stdenv.hostPlatform == pkgs.stdenv.buildPlatform) pkgs.unixbench
      # Build VLC only on x86
      ++ lib.optional (config.nixpkgs.hostPlatform.system == "x86_64-linux") pkgs.vlc;
  };
}
