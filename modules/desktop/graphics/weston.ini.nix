# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.ghaf.graphics.weston;
  mkLauncher = {
    # Add the name field to unify with Labwc launchers
    name,
    path,
    icon,
  }: ''
    [launcher]
    name=${name}
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
      name = "terminal";
      path = "${pkgs.weston}/bin/weston-terminal";
      icon = "${pkgs.weston}/share/weston/icon_terminal.png";
    }
  ];
in {
  config = lib.mkIf cfg.enable {
    ghaf.graphics.launchers = defaultLauncher;
    environment.etc."xdg/weston/weston.ini" = {
      text =
        ''
          # Disable screen locking
          [core]
          idle-time=0

          [shell]
          locking=false
          background-image=${../../../assets/wallpaper.png}
          background-type=scale-crop
          num-workspaces=2

          # Set the keyboard layout for weston to US by default
          [keyboard]
          keymap_layout=us,fi

          # Enable Hack font for weston-terminal
          [terminal]
          font=Hack
          font-size=16

        ''
        + mkLaunchers config.ghaf.graphics.launchers;

      # The UNIX file mode bits
      mode = "0644";
    };
  };
}
