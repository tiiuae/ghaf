# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  lib,
  ...
}:
let
  vmIcons = config.ghaf.graphics.launcherVmIcons;
  vmIconName = vm: if vmIcons.${vm}.icon or null != null then vmIcons.${vm}.icon else "ghaf-vm-${vm}";
  # libcosmic falls back to Cosmic when the configured theme lacks an icon
  badgeIconThemes = lib.unique (
    [ pkgs.cosmic-icons ]
    ++ lib.optional (
      config.ghaf.theming.iconTheme.package != null
    ) config.ghaf.theming.iconTheme.package
  );

  toDesktop =
    launcherElem:
    let
      vm = if launcherElem.vm != null then lib.removeSuffix "-vm" launcherElem.vm else null;
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
      inherit (launcherElem) desktopName;
      comment = launcherElem.description;
      extraConfig = lib.optionalAttrs (vm != null && vmIcons ? ${vm}) {
        X-Ghaf-VM = vm;
        X-Ghaf-VM-Icon = vmIconName vm;
      };
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

  vmBadgeIcons = pkgs.runCommand "ghaf-vm-badge-icons" { allowedReferences = [ ]; } (
    lib.concatStrings (
      lib.mapAttrsToList (vm: v: ''
        install -Dm444 ${pkgs.writeText "ghaf-vm-${vm}.svg" ''
          <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><circle cx="8" cy="8" r="6.5" fill="${
            if v.color != null then v.color else "#808080"
          }" stroke="#ffffff" stroke-width="1.5"/></svg>
        ''} $out/share/icons/hicolor/scalable/apps/ghaf-vm-${vm}.svg
      '') (lib.filterAttrs (_: v: v.icon == null) vmIcons)
    )
    + lib.concatMapStrings (name: ''
      find -L ${lib.escapeShellArgs badgeIconThemes} -path '*/share/icons/*' \
        \( -name ${lib.escapeShellArg "${name}.svg"} -o -name ${lib.escapeShellArg "${name}.png"} \) |
        grep -q . || {
          echo ${lib.escapeShellArg "no icon named ${name} in the gui-vm icon themes"} >&2
          exit 1
        }
    '') (lib.unique (lib.filter (i: i != null) (lib.mapAttrsToList (_: v: v.icon) vmIcons)))
    + ''
      mkdir -p $out
    ''
  );
in
pkgs.symlinkJoin {
  name = "ghaf-desktop-entries";
  paths = map toDesktop config.ghaf.graphics.launchers ++ [
    icons
    vmBadgeIcons
  ];
}
