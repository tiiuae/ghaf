# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.ghaf.graphics.weston;
  mkLauncher = {
    path,
    icon,
  }: ''
    [launcher]
    path=${path}
    icon=${icon}

  '';

  /*
  Generate launchers to be used in weston.ini

  Type: mkLaunchers :: [{path, icon}] -> string

  */
  mkLaunchers = lib.concatMapStrings mkLauncher;

  defaultLauncher = [
    # Keep weston-terminal launcher always enabled explicitly since if someone adds
    # a launcher on the panel, the launcher will replace weston-terminal launcher.
    {
      path = "${pkgs.weston}/bin/weston-terminal";
      icon = "${pkgs.weston}/share/weston/icon_terminal.png";
    }
  ];
in {
  options.ghaf.graphics.weston = with lib; {
    launchers = mkOption {
      description = "Weston application launchers to show in launch bar";
      default = [];
      type = with types;
        listOf
        (submodule {
          options.path = mkOption {
            description = "Path to the executable to be launched";
            type = path;
          };
          options.icon = mkOption {
            description = "Path of the icon";
            type = path;
          };
        });
    };
    enableDemoApplications = mkEnableOption "some applications for demoing";
  };

  config = lib.mkIf cfg.enable {
    ghaf.graphics.weston.launchers = defaultLauncher;
    environment.etc."xdg/weston/weston.ini" = {
      text =
        ''
          # Disable screen locking
          [core]
          idle-time=0

          [shell]
          locking=false
          background-image=${../../assets/wallpaper.png}
          background-type=scale-crop
          num-workspaces=2

          # Enable Hack font for weston-terminal
          [terminal]
          font=Hack
          font-size=16

        ''
        + mkLaunchers cfg.launchers;

      # The UNIX file mode bits
      mode = "0644";
    };
  };
}
