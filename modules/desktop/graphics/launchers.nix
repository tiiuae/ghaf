# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  makeDesktopItem,
  ...
}: let
  toDesktop = elem:
    (makeDesktopItem {
      inherit (elem) name icon;
      genericName = elem.name;
      desktopName = elem.name;
      comment = "Secured Ghaf Application";
      exec = elem.path;
    })
    .overrideAttrs (prevAttrs: {
      checkPhase =
        prevAttrs.checkPhase
        + ''

          # Check that the icon's path exists
          [[ -f "${elem.icon}" ]] || (echo "The icon's path ${elem.icon} doesn't exist" && exit 1)
        '';
    });
in
  pkgs.symlinkJoin {
    name = "ghaf-desktop-entries";
    paths = map toDesktop config.ghaf.graphics.launchers;
  }
