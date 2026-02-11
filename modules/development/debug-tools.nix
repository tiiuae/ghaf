# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.development.debug.tools;

  sysbench-test-script = pkgs.callPackage ./scripts/sysbench_test.nix { };
  sysbench-fileio-test-script = pkgs.callPackage ./scripts/sysbench_fileio_test.nix { };
  nvpmodel-check = pkgs.callPackage ./scripts/nvpmodel_check.nix { };
  fss-test = pkgs.callPackage ../../tests/logging/test_scripts/fss-test.nix { };

  inherit (lib) mkEnableOption mkIf rmDesktopEntries;
in
{
  _file = ./debug-tools.nix;

  options.ghaf.development.debug.tools = {
    enable = mkEnableOption "Debug Tools";
  };

  config = mkIf cfg.enable {
    environment.etc = {
      audio_test.source = ./audio_test;
    };
    environment.systemPackages = [
      # for finding and navigation
      pkgs.fd
      pkgs.ripgrep
      pkgs.file

      # Grpc testing
      pkgs.grpcurl

      pkgs.sysbench
      sysbench-test-script
      sysbench-fileio-test-script

      # FSS (Forward Secure Sealing) integrity test
      fss-test

      # For debug complicated issues
      pkgs.strace
    ]
    ++ rmDesktopEntries [
      pkgs.htop
    ]
    ++ lib.optionals (config.nixpkgs.hostPlatform.system != "aarch64-linux") [
      pkgs.kitty.terminfo
    ]
    ++ lib.optional (config.nixpkgs.hostPlatform.system == "aarch64-linux") nvpmodel-check;

    programs = {
      fzf = {
        fuzzyCompletion = true;
        keybindings = true;
      };
    };
  };
}
