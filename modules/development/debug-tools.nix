# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.development.debug.tools;

  rm-linux-bootmgrs = pkgs.callPackage ./scripts/rm_linux_bootmgr_entries.nix { };
  perf-test-script-icicle = pkgs.callPackage ./scripts/perf_test_icicle_kit.nix { };
  sysbench-test-script = pkgs.callPackage ./scripts/sysbench_test.nix { };
  sysbench-fileio-test-script = pkgs.callPackage ./scripts/sysbench_fileio_test.nix { };
  nvpmodel-check = pkgs.callPackage ./scripts/nvpmodel_check.nix { };

  inherit (lib) mkEnableOption mkIf;
  #TODO; make sure that the lib is exported correctly and remove this cross file import
  inherit (import ../../lib/launcher.nix { inherit pkgs lib; }) rmDesktopEntries;
in
{
  options.ghaf.development.debug.tools = {
    enable = mkEnableOption "Debug Tools";
  };

  config = mkIf cfg.enable {
    environment.etc = {
      audio_test.source = ./audio_test;
    };
    environment.systemPackages = [
      # For lspci:
      pkgs.pciutils
      # For lsusb:
      pkgs.usbutils
      # Useful in NetVM
      pkgs.nettools
      pkgs.ethtool
      # Basic monitors
      pkgs.iftop
      pkgs.iotop
      pkgs.traceroute
      pkgs.dig
      pkgs.evtest
      # for finding and navigation
      pkgs.fd
      (pkgs.ripgrep.override { withPCRE2 = true; })

      # For deleting Linux Boot Manager entries in automated testing
      pkgs.efibootmgr

      # Performance testing
      pkgs.ookla-speedtest
      pkgs.iperf
      pkgs.tree
      pkgs.file

      # to build ghaf on target
      pkgs.git

      # Grpc testing
      pkgs.grpcurl

      pkgs.lshw
      # Tools for joysticks and serial peripherals
      pkgs.linuxConsoleTools

      sysbench-test-script
      sysbench-fileio-test-script
      nvpmodel-check
      rm-linux-bootmgrs
    ]
    # v4l for camera testing
    ++ rmDesktopEntries [ pkgs.v4l-utils ]
    ++ rmDesktopEntries [ pkgs.htop ]
    #TODO tmp disable perf as it is broken in cross-compiled Orin AGX/NX
    ++ lib.optional (config.nixpkgs.hostPlatform.system != "aarch64-linux") pkgs.perf
    # LuaJIT (which is sysbench dependency) not available on RISC-V
    # ydotool and grim are tools for automated GUI-testing, useless on riscv
    ++ lib.optionals (config.nixpkgs.hostPlatform.system != "riscv64-linux") [
      pkgs.sysbench
      pkgs.ydotool
      pkgs.grim
    ]
    # Icicle Kit performance test script available on RISC-V
    ++ lib.optional (config.nixpkgs.hostPlatform.system == "riscv64-linux") perf-test-script-icicle
    # runtimeShell (unixbench dependency) not available on RISC-V nor on cross-compiled Orin AGX/NX
    ++ lib.optional (pkgs.stdenv.hostPlatform == pkgs.stdenv.buildPlatform) pkgs.unixbench
    # Build VLC only on x86. Ffmpeg7 and v4l for camera related testing only on x86
    ++ lib.optionals (config.nixpkgs.hostPlatform.system == "x86_64-linux") (rmDesktopEntries [
      pkgs.vlc
      pkgs.ffmpeg_7-full
      pkgs.kitty.terminfo
      #pkgs.ghostty.terminfo
    ]);

    programs = {
      fzf = {
        fuzzyCompletion = true;
        keybindings = true;
      };
    };
  };
}
