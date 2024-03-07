# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  makeDesktopItem,
  ...
}: let
  toDesktop = elem:
    if !builtins.pathExists elem.icon
    then throw "The icon's path ${elem.icon} doesn't exist"
    else
      makeDesktopItem {
        inherit (elem) name icon;
        genericName = elem.name;
        desktopName = elem.name;
        comment = "Secured Ghaf Application";
        exec = elem.path;
      };
in
  pkgs.symlinkJoin {
    name = "ghaf-desktop-entries";
    paths = map toDesktop config.ghaf.graphics.launchers;
  }
