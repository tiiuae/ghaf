# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.ghaf.power-profile;
  inherit (lib)
    mkEnableOption
    mkMerge
    mkIf
    mkForce
    mkDefault
    getExe
    concatMapStringsSep
    attrNames
    filterAttrs
    replaceString
    removeSuffix
    ;
  ghaf-powercontrol = pkgs.ghaf-powercontrol.override { ghafConfig = config.ghaf; };
  givc-cli = "${pkgs.givc-cli}/bin/givc-cli ${replaceString "/run" "/etc" config.ghaf.givc.cliArgs}";
  useGivc = config.ghaf.givc.enable;

  # VM fake suspend to override 'systemd-sleep suspend'
  vmFakeSuspend = pkgs.writeShellApplication {
    name = "vm-fake-suspend";
    text = ''
      echo "FAKE SUSPEND: Waiting for external stop signal..."

      stop_service() {
        echo "FAKE SUSPEND: Received stop signal..."
        exit 0
      }

      trap stop_service SIGTERM

      # Wait for the stop signal
      while true; do
        sleep 1
      done
    '';
  };
in
{
  options.ghaf.power-profile = {
    vm = mkEnableOption "VM power management profile";
    gui = mkEnableOption "GUI power management profile";
    host = mkEnableOption "Host power management profile";
  };

  config = mkMerge [

    {
      assertions = [
        {
          assertion = cfg.vm -> ((!cfg.gui) && (!cfg.host));
          message = "Enabling the VM power management profile ('ghaf.power-profile.vm') requires both 'gui' and 'host' profiles to be disabled.";
        }
      ];
    }

    # VM power management profile
    # This profile can be used for system or app VMs to implement custom actions
    # before and after suspend. For this, the powerManagement API can be used.
    (mkIf (cfg.vm && useGivc) {

      # Prohibited sleep actions for VMs
      systemd.sleep.extraConfig = ''
        AllowHibernation=no
        AllowHybridSleep=no
        AllowSuspendThenHibernate=no
      '';

      # Fake suspend for system VMs. This allows to run pre- and post-suspend commands
      # without actually suspending the VM internally (which does not work at the moment).
      systemd.services.systemd-suspend = {
        serviceConfig.ExecStart = mkForce [
          "" # This is needed to clear default systemd-sleep
          "${getExe vmFakeSuspend}"
        ];
      };
    })

    # GUI power management profile
    # This profile can be used for the desktop running on either gui-vm or host.
    # It replaces the default systemd actions for suspend, poweroff, and reboot
    # with ghaf-powercontrol commands, that forward the actions to the host.
    (mkIf cfg.gui {
      # Prohibited sleep actions for GUI
      systemd.sleep.extraConfig = ''
        AllowHibernation=no
        AllowHybridSleep=no
        AllowSuspendThenHibernate=no
      '';

      # Override systemd actions for suspend, poweroff, and reboot
      systemd.services.systemd-suspend = {
        serviceConfig.ExecStart = mkForce [
          "" # Clear the default
          "${getExe ghaf-powercontrol} suspend"
        ];
      };
      systemd.services.systemd-poweroff = {
        serviceConfig.ExecStart = mkForce [
          "" # Clear the default
          "${getExe ghaf-powercontrol} poweroff"
        ];
      };
      systemd.services.systemd-reboot = {
        serviceConfig.ExecStart = mkForce [
          "" # Clear the default
          "${getExe ghaf-powercontrol} reboot"
        ];
      };

      # Logind configuration for GUI
      services.logind = {
        lidSwitch = "suspend";
        killUserProcesses = true;
        extraConfig = ''
          IdleAction=lock
          UserStopDelaySec=0
        '';
      };
    })

    # Host power management
    (mkIf (cfg.host && useGivc) {
      services.logind.lidSwitch = mkDefault "ignore";

      # Power management commands to VMs
      powerManagement = {

        # Signal VMs to suspend prior to host suspend
        # TODO Fix workaround (& and sleep). Also, this will fail if the VM actually suspends,
        # which currently does not work because of virtiofs
        powerDownCommands =
          concatMapStringsSep "\n" (vmName: ''
            echo "Signaling suspend to ${vmName}..."
            ${givc-cli} start service --vm "${removeSuffix "-vm" vmName}" suspend.target &
          '') (attrNames (filterAttrs (_n: v: v.config.config.ghaf.power-profile.vm) config.microvm.vms))
          + "${pkgs.coreutils}/bin/sleep 1";

        # Signal VMs to resume. At this point, the VMs are already running but we want to exit
        # the suspend service and trigger the resume commands
        # TODO givc-cli does not support stopping services, so we use grpcurl until fixed
        resumeCommands = concatMapStringsSep "\n" (vmName: ''
          echo "Signaling suspend to ${vmName}..."
          ${getExe pkgs.grpcurl} -cacert /etc/givc/ca-cert.pem -cert /etc/givc/cert.pem -key /etc/givc/key.pem \
          -d '{"UnitName":"systemd-suspend.service"}' ${vmName}:9000 systemd.UnitControlService.StopUnit
        '') (attrNames (filterAttrs (_n: v: v.config.config.ghaf.power-profile.vm) config.microvm.vms));
      };
    })
  ];
}
