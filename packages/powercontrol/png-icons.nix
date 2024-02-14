# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenv,
  pkgs,
  ...
}: let
  shutdownIconName = "system-shutdown-symbolic";
  rebootIconName = "system-reboot-symbolic";

  iconColor = "white";

  changeColorCcs = "path { fill: ${iconColor} !important; }";
  changeColorCcsPath = "$out/bin/color.css";

  getIconPath = {iconName}: "bin/${iconName}.png";
in
  stdenv.mkDerivation {
    name = "powercontrol-png-icons";

    phases = ["installPhase"];

    relativeShutdownIconPath = getIconPath {iconName = shutdownIconName;};
    relativeRebootIconPath = getIconPath {iconName = rebootIconName;};

    installPhase = let
      adwaitaRoot = "${pkgs.gnome.adwaita-icon-theme}/share/icons/Adwaita/symbolic/actions/";
      convertIconCommand = {iconName}: let
        outIconPath = getIconPath {inherit iconName;};
      in "${pkgs.librsvg}/bin/rsvg-convert --stylesheet=${changeColorCcsPath} ${adwaitaRoot}/${iconName}.svg -o $out/${outIconPath}";

      shutdown = convertIconCommand {iconName = shutdownIconName;};
      reboot = convertIconCommand {iconName = rebootIconName;};
    in ''
      mkdir -p $out/bin;

      echo '${changeColorCcs}' > ${changeColorCcsPath};

      ${shutdown};
      ${reboot};
    '';

    meta = {
      description = "Icons for power control";
      inherit (pkgs.gnome.adwaita-icon-theme.meta) license;
      inherit (pkgs.librsvg.meta) platforms;
    };
  }
