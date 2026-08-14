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
  _file = ./mem-manager.nix;

  systemd.services =
    builtins.foldl'
      (
        result: name:
        result
        // (
          let
            vmConfig = lib.ghaf.vm.getConfig config.microvm.vms.${name};
            microvmConfig = vmConfig.microvm;
            # Use enabledVms which has derived mem from evaluatedConfig
            vmBaseName = lib.removeSuffix "-vm" name;
            appvmConfig = config.ghaf.virtualization.microvm.appvm.enabledVms.${vmBaseName} or null;
            crosvmArgs = lib.optionals (microvmConfig.hypervisor == "crosvm") [
              "--hypervisor"
              "crosvm"
              "--crosvm-binary"
              (lib.getExe microvmConfig.crosvm.package)
            ];
            managerArgs = [
              (lib.getExe pkgs.ghaf-mem-manager)
              "--socket"
              "${name}.sock"
              "--minimum"
              (toString (appvmConfig.mem * 1024 * 1024))
              "--maximum"
              (toString (microvmConfig.mem * 1024 * 1024))
            ]
            ++ crosvmArgs;
          in
          lib.optionalAttrs (appvmConfig != null) {
            "ghaf-mem-manager-${name}" = {
              description = "Manage MicroVM '${name}' memory levels";
              after = [ "microvm@${name}.service" ];
              requires = [ "microvm@${name}.service" ];
              serviceConfig = {
                Type = "simple";
                WorkingDirectory = "${config.microvm.stateDir}/${name}";
                ExecStart = lib.escapeShellArgs managerArgs;
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
