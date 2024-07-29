# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This package contains only the assets that we need from papirus-icon-theme,
# so we don't include the entire theme in the distribution.
{
  lib,
  runCommand,
  papirus-icon-theme,
}:
let
  icons = [
    "chromium.svg"
    "distributor-logo-android.svg"
    "distributor-logo-windows.svg"
    "document-viewer.svg"
    "element-desktop.svg"
    "firefox.svg"
    "microsoft-365.svg"
    "ms-outlook.svg"
    "preferences-system-network.svg"
    "system-lock-screen.svg"
    "system-log-out.svg"
    "system-reboot.svg"
    "system-shutdown.svg"
    "system-suspend-hibernate.svg"
    "system-suspend.svg"
    "teams-for-linux.svg"
    "thorium-browser.svg"
    "utilities-terminal.svg"
    "yast-vpn.svg"
  ];
in
runCommand "icon-pack"
  {
    # Preserve Papirus license
    meta.license = papirus-icon-theme.meta.license;
  }
  ''
    mkdir -p $out
    # All SVGs are located inside 64x64, all other sizes are symlinks.

    ${lib.concatStringsSep "\n" (
      map (icon: ''
        cp ${papirus-icon-theme}/share/icons/Papirus/64x64/apps/${icon} $out/
      '') icons
    )}
  ''
