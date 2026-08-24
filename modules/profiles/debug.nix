# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.profiles.debug;
in
{
  _file = ./debug.nix;

  options.ghaf.profiles.debug = {
    # No implicit default: a composition that selects neither profile gets
    # neither the debug stack (ssh, serial, debug tools) nor release gates.
    enable = lib.mkEnableOption "debug profile";
  };

  config = lib.mkMerge [
    {
      # Outside the mkIf: this has to fire precisely when neither profile is
      # selected, which is when that branch is dead. Both profiles are what
      # turn on the minimal base (minimal.nix has no other setter), so a
      # profile-less composition silently loses documentation.enable = false,
      # the defaultPackages mkForce and boot.enableContainers = false -- i.e.
      # it gets a *larger* image, not a smaller one, plus no debug access.
      warnings = lib.optional (!cfg.enable && !config.ghaf.profiles.release.enable) ''
        No Ghaf profile is selected: ghaf.profiles.debug.enable and
        ghaf.profiles.release.enable are both false, so neither the debug stack
        (ssh, serial console, debug tools) nor the minimal base is applied.
        Set one of them explicitly.
      '';
    }

    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = !config.ghaf.profiles.release.enable;
          message = "The debug and release profiles are mutually exclusive.";
        }
      ];

      # Enable minimal profile as base
      ghaf.profiles.minimal.enable = true;

      # Encryption: non-interactive setup with debug tools in debug profile
      ghaf.storage.encryption.interactiveSetup = lib.mkDefault false;
      ghaf.storage.encryption.debugTools = lib.mkDefault true;

      # Enable default accounts and passwords
      ghaf = {
        # Enable development on target
        # TODO: we should import the module that defines the development namespace
        # see the graphics.nix example including the desktop module to get ghaf.graphics
        nix.enable = true;

        development = {
          # Enable some basic monitoring and debug tools
          debug.tools.enable = true;
        };

        # Let us in (unprotected debug SSH: password + dev keys).
        security.ssh.debug.enable = true;
      };
    })
  ];
}
