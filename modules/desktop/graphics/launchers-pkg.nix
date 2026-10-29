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
      prefix =
        if launcherElem.vm != null then "[${lib.strings.removeSuffix "-vm" launcherElem.vm}] " else "";
      icon = iconName launcherElem;

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
        genericName
        categories
        exec
        noDisplay
        onlyShowIn
        ;
      inherit icon startupWMClass;
      desktopName = "${prefix}${launcherElem.desktopName}";
      comment = if launcherElem.description != null then "${prefix}${launcherElem.description}" else null;
    }).overrideAttrs
      (prevAttrs: {
        checkPhase = prevAttrs.checkPhase + extraCheckPhase;
      });
  iconName =
    launcherElem:
    if launcherElem.icon != null then
      launcherElem.icon
    else
      (lib.strings.toLower (lib.replaceStrings [ " " ] [ "-" ] launcherElem.desktopName));

  namedIconLaunchers = lib.filter (
    l: !l.noDisplay && !lib.hasPrefix "/" (iconName l)
  ) config.ghaf.graphics.launchers;

  # Apps from other VMs have their icons only in their own VM, so copy them here.
  # Web apps ship no package and some names exist only in an icon theme.
  icons =
    pkgs.runCommand "ghaf-launcher-icons"
      {
        allowedReferences = [ ];
      }
      ''
        pick() {
          local name=$1 root src
          shift
          for root in "$@"; do
            src=$(find -L "$root/share/icons" "$root/share/pixmaps" -type f \
              \( -name "$name.svg" -o -name "$name.png" \) 2>/dev/null |
              awk '{ s = /\.svg$/ ? 100000 : 0
                     if (match($0, /\/[0-9]+x[0-9]+\//)) s += substr($0, RSTART + 1, RLENGTH - 2) + 0
                     print s "\t" $0 }' |
              sort -rn | head -1 | cut -f2 || true)
            [[ -n $src ]] && echo "$src" && return
          done
          return 1
        }

        install_icon() {
          local name=$1
          shift
          local src size
          src=$(pick "$name" "$@" ${pkgs.pop-icon-theme} ${pkgs.papirus-icon-theme}) || {
            echo "no icon named $name in its packages, Pop or Papirus" >&2
            exit 1
          }
          if [[ $src == *.svg ]]; then
            install -Dm444 "$src" "$out/share/icons/hicolor/scalable/apps/$name.svg"
          else
            size=$(grep -o '/[0-9]*x[0-9]*/' <<<"$src" | tr -d / | cut -dx -f1)
            size=$(( ''${size:-512} > 512 ? 512 : ''${size:-512} ))
            install -Dm444 "$src" "$out/share/icons/hicolor/''${size}x''${size}/apps/$name.png"
          fi
        }

        ${lib.concatMapStringsSep "\n" (
          l: "install_icon ${lib.escapeShellArgs ([ (iconName l) ] ++ map toString l.packages)}"
        ) namedIconLaunchers}
      '';
in
pkgs.symlinkJoin {
  name = "ghaf-desktop-entries";
  paths = map toDesktop config.ghaf.graphics.launchers ++ [ icons ];
}
