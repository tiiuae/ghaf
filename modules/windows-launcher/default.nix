# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.ghaf.windows-launcher;
  windows-launcher = pkgs.callPackage ../../user-apps/windows-launcher {};
in {
  options.ghaf.windows-launcher = {
    enable = lib.mkEnableOption "Windows launcher";
  };

  config = lib.mkIf cfg.enable {
    ghaf.graphics.weston.launchers = [
      {
        path = "${windows-launcher}/bin/windows-launcher-ui";
        icon = "${pkgs.gnome.adwaita-icon-theme}/share/icons/Adwaita/16x16/mimetypes/application-x-executable.png";
      }
    ];
    environment.systemPackages = [windows-launcher];
  };
}
