# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{pkgs, ...}: {
  environment.etc."xdg/weston/weston.ini" = {
    text = ''
      # Disable screen locking
      [core]
      idle-time=0

      [shell]
      locking=false

      # Enable Hack font for weston-terminal
      [terminal]
      font=Hack
      font-size=16

      # Add application launchers
      # Adding terminal launcher because it is overwritten if other launchers are on the panel
      [launcher]
      path=${pkgs.weston}/bin/weston-terminal
      icon=${pkgs.weston}/share/weston/icon_terminal.png

      [launcher]
      path=${pkgs.chromium}/bin/chromium --enable-features=UseOzonePlatform --ozone-platform=wayland
      icon=${pkgs.chromium}/share/icons/hicolor/24x24/apps/chromium.png

      [launcher]
      path=${pkgs.element-desktop}/bin/element-desktop --enable-features=UseOzonePlatform --ozone-platform=wayland
      icon=${pkgs.element-desktop}/share/icons/hicolor/24x24/apps/element.png
    '';

    # The UNIX file mode bits
    mode = "0644";
  };
}
