# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.reference.programs.windows-launcher;
  windows-launcher = pkgs.callPackage ../../../packages/windows-launcher { enableSpice = cfg.spice; };
in
{
  #TODO fix all these imports to correct scoping
  imports = [ ../../desktop ];

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
      default = "192.168.101.2";
    };
  };

  config = lib.mkIf cfg.enable {
    ghaf.graphics.launchers = lib.mkIf (!cfg.spice) [
      {
        name = "Windows";
        path = "${windows-launcher}/bin/windows-launcher-ui";
        icon = "${pkgs.icon-pack}/distributor-logo-windows.svg";
      }
    ];

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.spice [ cfg.spice-port ];
    environment.systemPackages = [ windows-launcher ];
  };
}
