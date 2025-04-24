# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.boot;
  inherit (lib)
    mkEnableOption
    mkIf
    mkForce
    attrNames
    optionalAttrs
    optionalString
    ;
  inherit (config.ghaf) logging;
  inherit (config.ghaf.networking) hosts;
  inherit (config.ghaf.virtualization.microvm) appvm;
in
{
  options.ghaf.boot = {
    enable = mkEnableOption "Enable ghaf-specific microvm boot order.";
  };

  config = mkIf cfg.enable {

    systemd.targets = {
      # Target to delay AppVM startup
      appvm-startup = {
        description = "AppVM startup";
        requiredBy = [ "microvms.target" ];
        requires = [ "appvm-startup.service" ];
        after = [ "appvm-startup.service" ];
      };

      # Override microvm.nix's default target (default is only VMs with autostart)
      microvms = {
        wants = mkForce (map (name: "microvm@${name}.service") (attrNames config.microvm.vms));
      };
    };

    systemd.services =
      {
        # Service to wait for gui-vm to reach greetd.service
        appvm-startup = {
          description = "AppVM startup";
          serviceConfig = {
            type = "oneshot";
            ExecStartPre = optionalString appvm.enable ''
              ${pkgs.wait-for-unit}/bin/wait-for-unit \
              ${hosts.admin-vm.ipv4} 9001 \
              gui-vm \
              greetd.service
            '';
            ExecStart = "/bin/sh -c exit"; # no-op
            RemainAfterExit = true;
          };
        };

        # Delay logging service on host
        alloy = optionalAttrs logging.enable {
          after = [ "microvms.target" ];
        };
      }
      // builtins.foldl' (
        result: name:
        result
        // {
          # Prevent microvm restart if shutdown internally. If set to 'on-failure', 'microvm-shutdown'
          # in ExecStop of the microvm@ service fails and causes the service to restart.
          "microvm@${name}".serviceConfig = {
            Restart = "on-abnormal";
          };
        }
      ) { } (builtins.attrNames config.microvm.vms);
  };
}
