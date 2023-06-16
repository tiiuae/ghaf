# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  lib,
  pkgs,
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
      #TODO Should we assert dependency on graphics (weston) profile?
      #For now enable weston + apps
      ghaf.graphics.weston = {
        enable = true;
        enableDemoApplications = true;
      };
    };
  }
