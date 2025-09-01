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
  cfg = config.ghaf.services.power-manager;
  inherit (lib)
    attrNames
    concatStringsSep
    concatMapStringsSep
    filterAttrs
    flatten
    getExe
    literalExpression
    listToAttrs
    mkDefault
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    nameValuePair
    optionalAttrs
    optionals
    optionalString
    replaceString
    types
    ;

  useGivc = config.ghaf.givc.enable;
  givc-cli = "${pkgs.givc-cli}/bin/givc-cli ${replaceString "/run" "/etc" config.ghaf.givc.cliArgs}";
  ghaf-powercontrol = pkgs.ghaf-powercontrol.override { ghafConfig = config.ghaf; };

  # List of all passthrough nic and audio PCI devices. The generated list of "vendorId:productId" strings
  # is used to determine suspend actions for PCI devices at runtime
  pciDevices = flatten (
    map (device: "${device.vendorId}:${device.productId}") (
      config.ghaf.common.hardware.nics ++ config.ghaf.common.hardware.audio
    )
  );

  # List of VMs that are running a fake suspend
  fakeSuspendVms = attrNames (
    filterAttrs (
      _n: v:
      (
        v.config.config.ghaf.services.power-manager.vm.enable
        && v.config.config.ghaf.services.power-manager.vm.fakeSuspend
      )
    ) config.microvm.vms
  );

  # List of VMs that are running a PCI suspend
  pciSuspendVms = attrNames (
    filterAttrs (
      _n: v:
      (
        v.config.config.ghaf.services.power-manager.vm.enable
        && v.config.config.ghaf.services.power-manager.vm.pciSuspend
      )
    ) config.microvm.vms
  );

  # List of VMs that are powered off on suspend
  powerOffVms = attrNames (
    filterAttrs (
      _n: v:
      (
        v.config.config.ghaf.services.power-manager.vm.enable
        && v.config.config.ghaf.services.power-manager.vm.powerOffOnSuspend
      )
    ) config.microvm.vms
  );

  # Host suspend actions
  host-suspend-actions = pkgs.writeShellApplication {
    name = "host-suspend-actions";
    runtimeInputs = [
      givc-cli
      pkgs.systemd
      pkgs.coreutils
      pkgs.grpcurl
      pkgs.hotplug
      pkgs.wait-for-unit
    ];
    text = ''
      if [[ $# -lt 3 || -z "$1" || -z "$2" || -z "$3" ]]; then
        echo "Usage: $0 <VM Name> <suspend-action> (suspend|resume) "
        exit 1
      fi
      vm_name="$1"
      suspend_action="$2"
      action="$3"

      # Execute host suspend actions
      case "$suspend_action" in

        poweroff)
          case "$action" in
            suspend)
              echo "Powering off $vm_name..."
              systemctl stop microvm@"$vm_name".service
              ;;
            resume)
              echo "Restarting $vm_name..."
              systemctl restart microvm@"$vm_name".service
              ;;
            *)
              echo "Invalid action: $action"
              echo "Usage: $0 <VM Name> <suspend-action> (suspend|resume)"
              exit 1
              ;;
          esac
          ;;

        fake-suspend)
          case "$action" in
            suspend)
              echo "Signaling suspend to $vm_name..."
              vm=''${vm_name/-vm/}
              ${givc-cli} start service --vm "$vm" suspend.target &
              # Wait until suspend is active
              ${getExe pkgs.wait-for-unit} ${config.ghaf.networking.hosts.admin-vm.ipv4} 9001 \
              "$vm_name" systemd-suspend.service 5 \
              activating start
              ;;
            resume)
              echo "Signaling resume to $vm_name..."
              # Stop unit command not yet implemented in GIVC admin service
              grpcurl -cacert /etc/givc/ca-cert.pem -cert /etc/givc/cert.pem -key /etc/givc/key.pem \
              -d '{"UnitName":"systemd-suspend.service"}' "$vm_name":9000 systemd.UnitControlService.StopUnit
              ;;
            *)
              echo "Invalid action: $action"
              echo "Usage: $0 <VM Name> {suspend|resume}"
              exit 1
              ;;
          esac
          ;;

        pci-suspend)
          socket_path="${config.microvm.stateDir}/$vm_name/$vm_name.sock"
          state_path="${config.microvm.stateDir}/$vm_name/pci-state"
          case "$action" in
            suspend)
              declare -a pci_devices
              ${concatMapStringsSep "\n" (pciDevice: ''
                pci_devices+=("${pciDevice}")
              '') pciDevices}

              echo "Suspending PCI devices for $vm_name..."
              hotplug --detach-pci "''${pci_devices[@]}" --data-path "$state_path" --socket-path "$socket_path"
              ;;
            resume)
              echo "Resuming PCI devices for $vm_name..."
              if ! hotplug --attach-pci --data-path "$state_path" --socket-path "$socket_path"; then
                echo "Failed to attach PCI devices for $vm_name. Please check the logs."
                # Recovery from failed attach; restart the VM
                echo "Fallback: restarting $vm_name..."
                systemctl restart microvm@"$vm_name".service
              fi
              ;;
            *)
              echo "Invalid action: $action"
              echo "Usage: $0 <VM Name> <suspend-action> (suspend|resume)"
              exit 1
              ;;
          esac
        ;;

      *)
        echo "Invalid action: $suspend_action"
        echo "Usage: $0 <VM Name> <suspend-action> (suspend|resume)"
        exit 1
        ;;
      esac
      exit 0
    '';
  };

  # VM fake suspend to override 'systemd-sleep suspend'
  guest-fake-suspend = pkgs.writeShellApplication {
    name = "guest-fake-suspend";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      echo "VM FAKE-SUSPEND: Waiting for external resume signal..."
      stop_service() {
        echo "VM FAKE-SUSPEND: Received resume signal..."
        exit 0
      }
      trap stop_service SIGTERM
      while true; do sleep 1; done
    '';
  };

  guest-power-actions = pkgs.writeShellApplication {
    name = "guest-power-actions";
    runtimeInputs = [
      pkgs.pci-binder
    ];
    text = ''
      case "$1" in
        reboot|poweroff)
          # Signal host to power off or reboot the system
          ${givc-cli} "$1" &
          # This is a workaround since the givc-cli does support async requests,
          # and does not return when starting a reboot or poweroff target
          sleep 1
          ;;
        suspend)
          # Script to unbind PCI devices for suspend
          # For convenience, we pass IDs of all passthrough PCI devices,
          # each guest will automatically determine the correct PCI devices
          pci-binder unbind ${concatStringsSep " " pciDevices}
          ;;
        *)
          echo "Usage: $0 (suspend|reboot|poweroff)"
          exit 1
          ;;
      esac
      exit 0
    '';
  };

  guest-shutdown-interceptor = pkgs.writeShellApplication {
    name = "guest-shutdown-interceptor";
    runtimeInputs = [
      pkgs.systemd
      pkgs.coreutils
    ];
    text = ''
      # Determine the action to take based on systemd jobs
      if systemctl list-jobs | grep -q 'reboot.target.*start'; then
        echo "Reboot action: Relaying reboot to the host"
        ${getExe guest-power-actions} reboot
      elif systemctl list-jobs | grep -q 'poweroff.target.*start'; then
        echo "Poweroff action: Relaying poweroff to the host"
        ${getExe guest-power-actions} poweroff
      else
        # Ignore any other case
        exit 0
      fi
    '';
  };

in
{
  options.ghaf.services.power-manager = {

    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to enable the ghaf power management module. This module provides a set of power management profiles
        that can be used to manage the systems suspend, resume, and poweroff actions across the system. It only has
        effect for a guest or host configuration if one of the profiles is enabled.
      '';
      example = literalExpression ''
        # In host
        config.ghaf.services.power-manager.enable = true;

        # In GUI VM
        config.ghaf.services.power-manager = {
          vm.enable = true;
          gui.enable = true;
        };

        # In system VM A
        config.ghaf.services.power-manager.vm.enable = true;

        # In system VM B
        config.ghaf.services.power-manager = {
          vm = {
            enable = true;
            pciSuspend = false;
          };
        };
      '';
    };

    allowSuspend = mkOption {
      type = types.bool;
      default = config.ghaf.profiles.graphics.allowSuspend;
      defaultText = "config.ghaf.profiles.graphics.allowSuspend";
      description = ''
        Whether to allow the system to suspend. This is enabled if the option config.ghaf.profiles.graphics.allowSuspend is set.
        If disabled, the system will not respond to suspend requests, and all VMs with a power management profile enabled are
        prohibited to perform any suspend action.
      '';
    };

    vm = {
      enable = mkEnableOption ''
        VM power management profile. This profile can be used for guests to implement custom actions
        before and after suspend using the `powerManagement` options, suspend PCI devices, and/or power
        a VM off on suspend
      '';
      fakeSuspend = mkOption {
        type = types.bool;
        default = useGivc && !cfg.vm.powerOffOnSuspend && !cfg.gui.enable;
        defaultText = "useGivc && !cfg.vm.powerOffOnSuspend && !cfg.gui.enable";
        description = ''
          Whether to enable fake suspend for guests. This allows to run pre- and post-suspend commands, coordinated with the host
          but without actually suspending the guest internally (which does not work reliably at the moment).
          This is enabled by default if the VM power management profile and GIVC is enabled. In a gui-vm, this is unnecessary
          as a blocking GIVC command are used to "suspend" the VM, which is equivalent to a fake suspend.
        '';
      };
      pciSuspend = mkOption {
        type = types.bool;
        default = cfg.vm.fakeSuspend;
        defaultText = literalExpression ''
          config.ghaf.services.power-manager.vm.fakeSuspend
        '';
        description = ''
          Whether to enable automatic PCI device suspend for VMs. This will affect all PCI devices that are passed through to
          the guest, and will unbind PCI drivers in the guest and hotplug the device in this host. This is a solution that allows
          many PCI devices to enter low power states during system suspend without suspending the guest itself.

          This option is enabled by default if the VM power management profile is enabled. Unless running in a gui-vm, it requires
          fakeSuspend and GIVC to be enabled for the coordination of guest driver binding and host PCI hotplug actions.
        '';
      };
      pciSuspendServices = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          List of services to stop before suspend and (re)start during resume. This is useful to gracefully shutdown services
          that access guest PCI devices. Other suspend/resume commands can be added through the `powerManagement` options,
          or wrapped into systemd services and added to this list.
        '';
      };
      powerOffOnSuspend = mkOption {
        type = types.bool;
        default = !useGivc;
        description = ''
          Whether to enable VM poweroff on suspend. This is useful for non-GIVC cases or other suspend-related issues.
          If enabled the VM will be powered off on suspend, and restarted by the host on resume, which results in longer
          suspend and resume times as the VM has to be fully stopped and restarted.
        '';
      };

      # Real Suspend can be added in the future if
      # - virtiofs supports suspend/resume
      # - virtiofs shares are unmounted and nix store is image based
      # - other guest storage backends are used

    };
    gui = {
      enable = mkEnableOption ''
        GUI power management profile. This profile can be used for the desktop running either in the gui-vm or host.
        If running in a VM and GIVC is enabled, it replaces the default systemd actions for suspend, poweroff, and
        reboot with givc commands.
      '';
    };
    host = {
      enable = mkEnableOption ''
        host power management profile. This profile manages the hosts pre- and post-suspend actions to coordinate guest
        suspend actions and devices
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [

    {
      assertions = [
        {
          assertion = cfg.vm.enable -> (!cfg.host.enable);
          message = "Enabling the VM power management profile ('ghaf.services.power-manager.vm.enable') requires the 'host' profile to be disabled.";
        }
        {
          assertion = cfg.vm.fakeSuspend -> useGivc;
          message = "Enabling the VM fake suspend ('ghaf.services.power-manager.vm.fakeSuspend') requires GIVC to be enabled in the system.";
        }
        {
          assertion = cfg.vm.fakeSuspend -> (!cfg.gui.enable);
          message = "Enabling the VM fake suspend ('ghaf.services.power-manager.vm.fakeSuspend') requires the GUI power management profile to be disabled.";
        }
        {
          assertion = cfg.vm.fakeSuspend -> (!cfg.vm.powerOffOnSuspend);
          message = "Enabling the VM fake suspend ('ghaf.services.power-manager.vm.fakeSuspend') requires the option ('ghaf.services.power-manager.vm.powerOffOnSuspend') to be disabled.";
        }
        {
          assertion = cfg.vm.pciSuspend -> (!cfg.vm.powerOffOnSuspend);
          message = "Enabling the VM pci suspend ('ghaf.services.power-manager.vm.pciSuspend') requires the option ('ghaf.services.power-manager.vm.powerOffOnSuspend') to be disabled.";
        }
      ];
    }

    # VM power management
    (mkIf cfg.vm.enable {

      assertions = [
        {
          assertion = cfg.vm.pciSuspend -> (config.microvm.socket != null);
          message = "PCI suspend ('ghaf.services.power-manager.vm.pciSuspend') requires a microvm socket (config.microvm.socket).";
        }
      ];

      # Prohibited sleep actions for VMs
      systemd.sleep.extraConfig = ''
        AllowHibernation=no
        AllowHybridSleep=no
        AllowSuspendThenHibernate=no
      ''
      + optionalString (!cfg.allowSuspend) ''
        AllowSuspend=no
      '';

      powerManagement = optionalAttrs cfg.vm.enable {
        powerDownCommands = optionalString cfg.vm.pciSuspend (
          concatMapStringsSep "\n" (service: ''
            echo "Stopping service ${service}..."
            systemctl stop ${service}
          '') cfg.vm.pciSuspendServices
        );
        resumeCommands = optionalString cfg.vm.pciSuspend (
          concatMapStringsSep "\n" (service: ''
            echo "Starting service ${service}..."
            systemctl start ${service}
          '') cfg.vm.pciSuspendServices
        );
      };

      systemd.services.systemd-suspend.serviceConfig = {

        # Suspend actions for the VMs
        ExecStart =
          optionals (!cfg.gui.enable) [
            "" # always clear the default systemd-sleep
          ]
          ++ optionals cfg.vm.fakeSuspend [
            "${getExe guest-fake-suspend}"
          ]
          ++ optionals (!cfg.vm.fakeSuspend) [
            "${pkgs.coreutils}/bin/true"
          ];

        # Pre-suspend actions for the VM
        ExecStartPre = optionals cfg.vm.pciSuspend [
          "${getExe guest-power-actions} suspend"
        ];
      };
    })

    # GUI power management profile
    (mkIf cfg.gui.enable {

      # Shutdown displays early before suspend
      powerManagement = {
        powerDownCommands = lib.mkBefore ''
          ${lib.getExe ghaf-powercontrol} turn-off-displays '*'
        '';
      };

      # Override systemd actions for suspend, poweroff, and reboot
      systemd.services = optionalAttrs (cfg.vm.enable && useGivc) {

        # Replace systemd-sleep with GIVC suspend
        systemd-suspend.serviceConfig.ExecStart = [
          ""
          "${givc-cli} suspend"
        ];

        # Intercept reboot or poweroff actions and relay it to the host
        gui-shutdown-interceptor = {
          description = "Ghaf GUI shutdown interceptor";
          wantedBy = [
            "reboot.target"
            "poweroff.target"
          ];
          before = [
            "reboot.target"
            "poweroff.target"
            "shutdown.target"
          ];
          unitConfig.DefaultDependencies = false;
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${getExe guest-shutdown-interceptor}";
          };
        };

      };

      # Logind configuration for desktop
      services.logind = {
        lidSwitch = if cfg.allowSuspend then "suspend" else "ignore";
        killUserProcesses = true;
        extraConfig = ''
          IdleAction=lock
          UserStopDelaySec=0
          HoldoffTimeoutSec=20
        '';
      };
    })

    # Host power management
    (mkIf cfg.host.enable {
      services.logind.lidSwitch = mkDefault "ignore";

      systemd.sleep.extraConfig = ''
        AllowHibernation=no
        AllowHybridSleep=no
        AllowSuspendThenHibernate=no
      ''
      + optionalString (!cfg.allowSuspend) ''
        AllowSuspend=no
      '';

      systemd.targets = optionalAttrs cfg.allowSuspend {
        "pre-sleep-actions" = {
          description = "Target for pre-sleep host actions";
          unitConfig.StopWhenUnneeded = true;
          wantedBy = [ "sleep.target" ];
          partOf = [ "sleep.target" ];
          wants =
            map (vmName: "pre-sleep-poweroff@${vmName}.service") powerOffVms
            ++ map (vmName: "pre-sleep-fake-suspend@${vmName}.service") fakeSuspendVms
            ++ map (vmName: "pre-sleep-pci-suspend@${vmName}.service") pciSuspendVms;
        };
        "post-resume-actions" = {
          description = "Target for post-resume host actions";
          unitConfig.StopWhenUnneeded = true;
          wantedBy = [ "sleep.target" ];
          wants =
            map (vmName: "post-resume-poweroff@${vmName}.service") powerOffVms
            ++ map (vmName: "post-resume-fake-suspend@${vmName}.service") fakeSuspendVms
            ++ map (vmName: "post-resume-pci-suspend@${vmName}.service") pciSuspendVms;
        };
      };

      systemd.services = optionalAttrs cfg.allowSuspend (
        listToAttrs (
          flatten (
            map
              (suspendAction: [
                (nameValuePair "pre-sleep-${suspendAction}@" {
                  description = "pre-sleep ${suspendAction} action for '%i'";
                  partOf = [ "pre-sleep-actions.target" ];
                  before = [ "sleep.target" ];
                  after = optionals (suspendAction == "pci-suspend") [ "pre-sleep-fake-suspend@%i.service" ];
                  serviceConfig = {
                    Type = "oneshot";
                    ExecStart = "${getExe host-suspend-actions} %i ${suspendAction} suspend";
                  };
                })
                (nameValuePair "post-resume-${suspendAction}@" {
                  description = "post-resume ${suspendAction} action for '%i'";
                  partOf = [ "post-resume-actions.target" ];
                  after = [ "suspend.target" ];
                  before = optionals (suspendAction == "pci-suspend") [ "post-resume-fake-suspend@%i.service" ];
                  serviceConfig = {
                    Type = "oneshot";
                    ExecStart = "${getExe host-suspend-actions} %i ${suspendAction} resume";
                  };
                })
              ])
              [
                "poweroff"
                "fake-suspend"
                "pci-suspend"
              ]
          )
        )
      );

      # Power management services
      # TODO Evaluate these services
      # powerManagement.powertop.enable = config.ghaf.profiles.debug.enable;
      # services.thermald.enable = true;
      # services.auto-cpufreq = {
      #   enable = true;
      #   settings = {
      #     battery = {
      #       governor = "powersave";
      #       turbo = "never";
      #     };
      #     charger = {
      #       governor = "performance";
      #       turbo = "auto";
      #     };
      #   };
      # };
    })
  ]);
}
