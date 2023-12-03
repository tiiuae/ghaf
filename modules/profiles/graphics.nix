# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.profiles.graphics;
  #compositors = ["weston" "gnome" "labwc"];
in
  with lib; {
    options.ghaf.profiles.graphics = {
      enable = mkEnableOption "Graphics profile";
      # Select which compositor to use
      # compositor = mkOption {
      #   type = types.enum compositors;
      #   default = "weston";
      #   description = ''
      #     Which Wayland compositor to use.

      #     Choose one of: ${lib.concatStringsSep "," compositors}
      #   '';
      # };
    };

    config = mkIf cfg.enable {
      ghaf.graphics.enable = true;
      #ghaf.graphics.weston.enable = cfg.compositor == "weston";
      #ghaf.graphics.gnome.enable = cfg.compositor == "gnome";
      #ghaf.graphics.labwc.enable = cfg.compositor == "labwc";
    };
  }
