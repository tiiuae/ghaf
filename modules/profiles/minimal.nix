# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.profiles.minimal;
  inherit (lib)
    mkEnableOption
    mkIf
    mkDefault
    mkForce
    ;
in
{
  _file = ./minimal.nix;

  options.ghaf.profiles.minimal = {
    enable = (mkEnableOption "minimal profile") // {
      default = false;
    };
  };

  config = mkIf cfg.enable {
    # Minimal profile provides the base configuration that all other profiles build upon
    # This profile should contain only the essential settings needed for a basic Ghaf system
    # As the upstream changes such as bashless, minimal and other optimizations are too drastic
    # we will manually add the ones here that are deemed safe and useful for all profiles.

    documentation = {
      enable = mkDefault false;
      doc.enable = mkDefault false;
      info.enable = mkDefault false;
      man.enable = mkDefault false;
      man.man-db.enable = mkDefault false;
      nixos.enable = mkDefault false;
    };

    environment = {
      # Perl is a default package.
      # TODO: reenable the below, once we sync with the test teams-for-linux
      defaultPackages = mkForce [ ];
      #corePackages = mkForce [ ];
      #stub-ld.enable = mkDefault false;
    };

    programs = {
      command-not-found.enable = mkDefault false;
      fish.generateCompletions = mkDefault false;
      # The lessopen package pulls in Perl.
      less.lessopen = mkDefault null;
    };

    # Disable automatic config generation
    system.tools.nixos-generate-config.enable = mkDefault false;

    boot = {
      loader.grub.enable = mkDefault false;
      # This pulls in nixos-containers which depends on Perl.
      enableContainers = mkDefault false;
    };

    # Provide a minimal set of system packages
    environment.systemPackages = [
      pkgs.busybox
      pkgs.openssh
    ];

    # The system cannot be rebuilt, these should be enabled
    # especially when making the storeDiskImages
    # TODO: enable this for storeDiskImages only
    #nix.enable = mkDefault false;
    #system.switch.enable = mkDefault false;

    ghaf = {
      # Add minimal base configuration here
      # Currently empty - will be populated as we move common settings from debug/release
    };
  };
}
