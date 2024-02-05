# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.ghaf.windows-launcher;
  windows-launcher = pkgs.callPackage ../../packages/windows-launcher {enableSpice = cfg.spice;};
in {
  options.ghaf.windows-launcher = {
    enable = lib.mkEnableOption "Windows launcher";
  };

  options.ghaf.windows-launcher.spice = lib.mkEnableOption "remote access to the virtual machine using spice";

  options.ghaf.windows-launcher.spice-port = lib.mkOption {
    description = "Spice port";
    type = lib.types.int;
    default = 5900;
  };

  options.ghaf.windows-launcher.spice-host = lib.mkOption {
    description = "Spice host";
    type = lib.types.str;
    default = "192.168.101.2";
  };

  config = lib.mkIf cfg.enable {
    ghaf.graphics.launchers = lib.mkIf (!cfg.spice) [
      {
        name = "windows";
        path = "${windows-launcher}/bin/windows-launcher-ui";
        icon = "${pkgs.gnome.adwaita-icon-theme}/share/icons/Adwaita/16x16/mimetypes/application-x-executable.png";
      }
    ];

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.spice [cfg.spice-port];
    environment.systemPackages = [windows-launcher];
  };
}
