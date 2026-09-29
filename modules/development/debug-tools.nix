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

  inherit (lib) mkEnableOption mkIf rmDesktopEntries;
in
{
  _file = ./debug-tools.nix;

  options.ghaf.development.debug.tools.enable = mkEnableOption "Debug Tools";

  config = mkIf cfg.enable {
    environment.etc = {
      audio_test.source = ./audio_test;
    };
    environment.systemPackages =
      with pkgs;
      [
        # for finding and navigation
        fd
        ripgrep
        file

        # Grpc testing
        grpcurl

        sysbench
        sysbench-test-script
        sysbench-fileio-test-script

        # For debug complicated issues
        strace

        # For comparing NixOS system closure differences between generations.
        # ghaf-rebuild runs this on the target to print its post-switch package diff.
        dix
      ]
      ++ rmDesktopEntries [
        htop
      ]
      ++ lib.optionals (config.nixpkgs.hostPlatform.system != "aarch64-linux") [
        kitty.terminfo
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
