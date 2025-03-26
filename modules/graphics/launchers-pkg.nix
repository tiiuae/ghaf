# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs, config, ... }:
let
  toDesktop =
    elem:
    let
      prefix = if elem.vm != null then "[${elem.vm}] " else "";
      icon = if elem.icon != null then elem.icon else elem.name;

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
      inherit (elem) name;
      genericName = elem.name;
      desktopName = elem.name;
      inherit icon;
      comment = "${prefix}${elem.description}";
      exec = elem.path;
    }).overrideAttrs
      (prevAttrs: {
        checkPhase = prevAttrs.checkPhase + extraCheckPhase;
      });
in
pkgs.symlinkJoin {
  name = "ghaf-desktop-entries";
  paths = map toDesktop config.ghaf.graphics.launchers;
}
