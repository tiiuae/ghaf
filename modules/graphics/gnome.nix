# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
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
    environment.systemPackages = with pkgs; [
    ];

    services.xserver.enable = true;
    services.xserver.displayManager.gdm = {
      enable = true;
      wayland = true;
    };
    services.xserver.desktopManager.gnome.enable = true;

    environment.gnome.excludePackages = with pkgs; [
      gnome-tour
      epiphany
      evolution
      evolutionWithPlugins
      evolution-data-server
      gnome.geary
      gnome.gnome-music
      gnome.gnome-contacts
      gnome.cheese
    ];
  };
}
