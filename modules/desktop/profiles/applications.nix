# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ config, lib, ... }:
let
  cfg = config.ghaf.profiles.applications;
in
{
  options.ghaf.profiles.applications = {
    enable = lib.mkEnableOption "Some sample applications";
    #TODO Create options to allow enabling individual apps
  };

  config = lib.mkIf cfg.enable {
    # TODO: Needs more generic support for defining application launchers
    #       across different window managers.
    ghaf = {
      profiles.graphics.enable = true;
      graphics.enableDemoApplications = true;
    };
  };
}
