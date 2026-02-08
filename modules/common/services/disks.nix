# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.services.disks;
  yaml = pkgs.formats.yaml { };
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;
in
{
  _file = ./disks.nix;

  options.ghaf.services.disks = {
    enable = mkEnableOption "Enable disk mount daemon";

    fileManager = mkOption {
      type = types.str;
      default = "xdg-open";
      description = "The program to open mounted directories";
    };
  };
  config = mkIf cfg.enable {

    services.udisks2.enable = true;

    environment.etc."udiskie.yml".source = yaml.generate "udiskie.yml" {
      program_options = {
        automount = true;
        # True - keep tray applet open indefinitely
        # "auto" - auto hide tray applet when no devices connected
        tray = true;
        menu = "flat";
        notify = true;
        file_manager = cfg.fileManager;
        menu_checkbox_workaround = false;
        # True - add a "Managed devices" submenu where
        # a list of connected USB devices resides.
        # False - connected USB devices will be shown
        # in the root udiskie applet menu
        menu_update_workaround = false;
        # Command to be executed on any device event
        # event_hook = "";
      };
      device_config = [
        {
          device_file = "/dev/loop*";
          ignore = true;
        }
      ];
      quickmenu_actions = [
        "browse"
        "mount"
        "unmount"
        "eject"
      ];
      notifications = {
        # Customize which notifications are shown for how long.
        # Possible values are:
        #   positive number         timeout in seconds
        #   false                   disable notification
        #   -1                      use the libnotify default timeout
        # device_added = false;
      };
    };

    systemd.user.services.udiskie = {
      enable = true;
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "1";
        ExecStart = "${pkgs.udiskie}/bin/udiskie -c /etc/udiskie.yml";
      };
      wantedBy = [ "ghaf-session.target" ];
      after = [
        "ghaf-session.target"
        "ewwbar.service"
      ];
      partOf = [ "ghaf-session.target" ];
    };
  };
}
