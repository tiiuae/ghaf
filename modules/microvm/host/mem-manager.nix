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

  services.dbus.packages = [ pkgs.ghaf-mem-manager ];

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
          in
          lib.optionalAttrs (appvmConfig != null) {
            "ghaf-mem-manager-${name}" = {
              description = "Manage MicroVM '${name}' memory levels";
              after = [
                "dbus.service"
                "ghaf-mem-manager.service"
                "ghaf-qemu-mplex-${name}.service"
                "microvm@${name}.service"
              ];
              requires = [
                "dbus.service"
                "ghaf-mem-manager.service"
                "ghaf-qemu-mplex-${name}.service"
                "microvm@${name}.service"
              ];
              serviceConfig = {
                Type = "oneshot";
                ExecStart = ''
                  ${lib.getExe' pkgs.systemd "busctl"} --system call \
                    ae.tii.MemManager \
                    / \
                    ae.tii.MemManager \
                    AttachVm \
                    stt \
                    ${config.microvm.stateDir}/${name}/${name}.mux \
                    ${toString (appvmConfig.mem * 1024 * 1024)} \
                    ${toString (microvmConfig.mem * 1024 * 1024)}
                '';
              };
            };
          }
        )
      )
      {
        ghaf-mem-manager = {
          description = "Ghaf memory manager daemon";
          after = [ "dbus.service" ];
          wants = [ "dbus.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.ghaf-mem-manager}/bin/ghaf-mem-managerd";
            Restart = "on-failure";
            RestartSec = "1s";
            Environment = [ "RUST_LOG=trace" ];
          };
        };

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
