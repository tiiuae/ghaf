# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# GNOME Desktop support
#
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.ghaf.graphics.gnome;
in {
  options.ghaf.graphics.gnome = {
    enable = lib.mkEnableOption "gnome";
  };

  config = lib.mkIf cfg.enable {
    hardware.opengl = {
      enable = true;
      driSupport = true;
    };

    environment.noXlibs = false;
    #environment.variables = rec {
    #  LIBGL_ALWAYS_INDIRECT = "0";
    #};

    services.xserver = {
      enable = true;
      displayManager.lightdm = {
        enable = true;
        greeters.gtk.enable = true;
      };
      desktopManager.gnome.enable = true;
      windowManager.qtile.enable = true;
    };
    
    users.extraUsers.ghaf.extraGroups = ["video"];
    users.extraUsers.lightdm.extraGroups = ["video"];
    environment.gnome.excludePackages = with pkgs; [
      gnome-tour
      gnome.geary
      gnome.gnome-music
      gnome.gnome-contacts
      gnome.cheese
    ];
  };
}