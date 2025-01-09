# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# VM memory usage monitor on host
#
{
  pkgs,
  config,
  ...
}:
let
  balloonvms = builtins.filter (
    name: (config.microvm.vms.${name}.config.config.microvm.balloonMem or 0) >= 0
  ) (builtins.attrNames (config.microvm.vms or { }));
in
{
  systemd.services =
    builtins.foldl'
      (
        result: name:
        result
        // (
          let
            microvmConfig = config.microvm.vms.${name}.config.config.microvm;
          in
          {
            "ghaf-mem-monitor-${name}" = {
              description = "Monitor MicroVM '${name}' memory levels";
              after = [ "microvm@${name}.service" ];
              requires = [ "microvm@${name}.service" ];
              serviceConfig = {
                Type = "simple";
                WorkingDirectory = "${config.microvm.stateDir}/${name}";
                ExecStart = "${pkgs.mem-monitor}/bin/ghaf-mem-monitor -s ${name}.sock -m ${
                  builtins.toString (microvmConfig.mem * 1024 * 1024)
                } -M ${builtins.toString ((microvmConfig.mem + microvmConfig.balloonMem) * 1024 * 1024)}";
              };
            };
          }
        )
      )
      {
        balloon-monitor =
          let
            balloonvmnames = builtins.map (name: "ghaf-mem-monitor-" + name + ".service") balloonvms;
          in
          {
            description = "Monitor MicroVM balloons";
            after = balloonvmnames;
            requires = balloonvmnames;
            wantedBy = [ "microvms.target" ];
            script = ":";
          };
      }
      balloonvms;
}
