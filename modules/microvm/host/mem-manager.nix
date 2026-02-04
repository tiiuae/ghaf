# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# VM memory usage manager on host
#
{
  pkgs,
  config,
  lib,
  ...
}:
let
  balloonvms = builtins.filter (
    name:
    let
      vmConfig = lib.ghaf.vm.getConfig config.microvm.vms.${name};
    in
    vmConfig != null && (vmConfig.microvm.balloon or false)
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
            vmConfig = lib.ghaf.vm.getConfig config.microvm.vms.${name};
            microvmConfig = vmConfig.microvm;
            appvmConfig = config.ghaf.virtualization.microvm.appvm.vms.${lib.removeSuffix "-vm" name};
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
                  toString (appvmConfig.ramMb * 1024 * 1024)
                } -M ${toString (microvmConfig.mem * 1024 * 1024)}";
              };
            };
          }
        )
      )
      {
        balloon-manager =
          let
            balloonvmnames = map (name: "ghaf-mem-manager-" + name + ".service") balloonvms;
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
