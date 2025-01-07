# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# VM memory usage monitor on host
#
{ pkgs, config, ... }:
{
  config = {
    environment.systemPackages = [ pkgs.mem-monitor ];
    systemd.services = {
      balloon-monitor =
        let
          balloonvms = builtins.map (name: "ghaf-mem-monitor@" + name + ".service") (
            builtins.filter (name: (config.microvm.vms.${name}.config.config.microvm.balloonMem or 0) >= 0) (
              builtins.attrNames config.microvm.vms
            )
          );
        in
        {
          description = "Monitor MicroVM balloons";
          after = balloonvms;
          requires = balloonvms;
          wantedBy = [ "microvms.target" ];
          script = ":";
        };
      "ghaf-mem-monitor@" = {
        description = "Monitor MicroVM '%i'";
        requires = [ "microvm@%i.service" ];
        after = [ "microvm@%i.service" ];
        serviceConfig = {
          Type = "simple";
          WorkingDirectory = "${config.microvm.stateDir}/%i";
          ExecStart = "${pkgs.mem-monitor}/bin/ghaf-mem-monitor -s %i.sock";
        };
      };
    };
  };
}
