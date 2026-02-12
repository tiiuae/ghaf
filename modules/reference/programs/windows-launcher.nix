# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.reference.programs.windows-launcher;
  windows-launcher = pkgs.windows-launcher.override { enableSpice = cfg.spice; };
in
{
  _file = ./windows-launcher.nix;

  options.ghaf.reference.programs.windows-launcher = {
    enable = lib.mkEnableOption "Windows launcher";

    spice = lib.mkEnableOption "remote access to the virtual machine using spice";

    spice-port = lib.mkOption {
      description = "Spice port";
      type = lib.types.int;
      default = 5900;
    };

    spice-host = lib.mkOption {
      description = "Spice host";
      type = lib.types.str;
      default = config.ghaf.networking.hosts."ghaf-host".ipv4;
    };
  };

  config = lib.mkIf cfg.enable {
    ghaf.graphics.launchers = lib.mkIf (!cfg.spice) [
      {
        name = "Windows";
        desktopName = "Windows";
        description = "Virtualized Windows System";
        exec = "${windows-launcher}/bin/windows-launcher-ui";
        icon = "distributor-logo-windows";
      }
    ];

    ghaf.firewall.allowedTCPPorts = lib.mkIf cfg.spice [ cfg.spice-port ];
    environment.systemPackages = [ windows-launcher ];
  };
}
