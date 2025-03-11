# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# VM memory usage manager on host
#
{
  pkgs,
  config,
  ...
}:
let
  balloonvms = builtins.filter (
    name: (config.microvm.vms.${name}.config.config.microvm.balloonMem or 0) > 0
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
            "ghaf-mem-manager-${name}" = {
              description = "Manage MicroVM '${name}' memory levels";
              after = [ "microvm@${name}.service" ];
              requires = [ "microvm@${name}.service" ];
              serviceConfig = {
                Type = "simple";
                WorkingDirectory = "${config.microvm.stateDir}/${name}";
                ExecStart = "${pkgs.ghaf-mem-manager}/bin/ghaf-mem-manager -s ${name}.sock -m ${
                  builtins.toString (microvmConfig.mem * 1024 * 1024)
                } -M ${builtins.toString ((microvmConfig.mem + microvmConfig.balloonMem) * 1024 * 1024)}";
              };
            };
          }
        )
      )
      {
        balloon-manager =
          let
            balloonvmnames = builtins.map (name: "ghaf-mem-manager-" + name + ".service") balloonvms;
          in
          {
            description = "Manage MicroVM balloons";
            after = balloonvmnames;
            requires = balloonvmnames;
            wantedBy = [ "microvms.target" ];
            script = ":";
          };
      }
      balloonvms;
}
