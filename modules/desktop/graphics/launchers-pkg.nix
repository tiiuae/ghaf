# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  lib,
  ...
}:
let
  toDesktop =
    launcherElem:
    let
      prefix = if launcherElem.vm != null then "[${launcherElem.vm}] " else "";
      icon =
        if launcherElem.icon != null then
          launcherElem.icon
        else
          (lib.strings.toLower (lib.replaceStrings [ " " ] [ "-" ] launcherElem.desktopName));

      startupWMClass =
        if launcherElem.startupWMClass != null then launcherElem.startupWMClass else launcherElem.name;

      extraCheckPhase =
        if builtins.isPath icon then
          ''
            # Check that the icon's path exists
            [[ -f "${icon}" ]] || (echo "The icon's path ${icon} doesn't exist" && exit 1)
          ''
        else
          "";
    in
    (pkgs.makeDesktopItem {
      inherit (launcherElem)
        name
        desktopName
        genericName
        categories
        exec
        ;
      inherit icon startupWMClass;
      comment = "${prefix}${launcherElem.description}";
    }).overrideAttrs
      (prevAttrs: {
        checkPhase = prevAttrs.checkPhase + extraCheckPhase;
      });
in
pkgs.symlinkJoin {
  name = "ghaf-desktop-entries";
  paths = map toDesktop config.ghaf.graphics.launchers;
}
