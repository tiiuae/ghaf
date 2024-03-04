# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.profiles.applications;
in
  with lib; {
    options.ghaf.profiles.applications = {
      enable = mkEnableOption "Some sample applications";
      #TODO Create options to allow enabling individual apps
      #weston.ini.nix mods needed
    };

    config = mkIf cfg.enable {
      # TODO: Needs more generic support for defining application launchers
      #       across different window managers.
      ghaf = {
        profiles.graphics.enable = true;
        graphics.enableDemoApplications = true;
      };
    };
  }
