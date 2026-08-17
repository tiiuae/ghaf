# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  pkgs,
  lib,
  options,
  ...
}:
let
  deviceManagerPackage =
    lib.attrByPath
      [
        "ghaf"
        "hardware"
        "passthrough"
        "deviceManager"
        "package"
      ]
      (
        if (config.microvm.hypervisor or null) == "crosvm" then pkgs.ghaf-device-manager else pkgs.vhotplug
      )
      config;
  cfg = config.ghaf.services.power-manager;
  inherit (lib)
    concatMapStringsSep
    filterAttrs
    flatten
    getExe
    literalExpression
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
    getExe'
    ;

  useGivc = config.ghaf.givc.enable;
  givc-cli = "${pkgs.givc-cli}/bin/givc-cli ${replaceString "/run" "/etc" config.ghaf.givc.cliArgs}";
  ghaf-powercontrol = pkgs.ghaf-powercontrol.override { ghafConfig = config.ghaf; };

  # List of all passthrough nic and audio PCI devices. The generated list of "vendorId:productId" strings
  # is used to determine suspend actions for PCI devices at runtime
  pciDevices = flatten (
    map (device: "${device.vendorId}:${device.productId}") (
      lib.filter (d: d.vendorId != null && d.productId != null) (
        config.ghaf.common.hardware.nics ++ config.ghaf.common.hardware.audio
      )
    )

  );

  # List of VMs that are running a fake suspend
  fakeSuspendVms = lib.attrNames (
    filterAttrs (
      _n: v:
      let
        vmConfig = lib.ghaf.vm.getConfig v;
      in
      vmConfig != null
      && vmConfig.ghaf.services.power-manager.vm.enable
      && vmConfig.ghaf.services.power-manager.vm.fakeSuspend
    ) config.microvm.vms
  );

  # List of VMs that are running a PCI suspend
  pciSuspendVms = lib.attrNames (
    filterAttrs (
      _n: v:
      let
        vmConfig = lib.ghaf.vm.getConfig v;
      in
      vmConfig != null
      && vmConfig.ghaf.services.power-manager.vm.enable
      && vmConfig.ghaf.services.power-manager.vm.pciSuspend
    ) config.microvm.vms
  );

  # List of VMs that are powered off on suspend
  powerOffVms = lib.attrNames (
    filterAttrs (
      _n: v:
      let
        vmConfig = lib.ghaf.vm.getConfig v;
      in
      vmConfig != null
      && vmConfig.ghaf.services.power-manager.vm.enable
      && vmConfig.ghaf.services.power-manager.vm.powerOffOnSuspend
    ) config.microvm.vms
  );

  # VMs that relay power events instead of acting on an ACPI power button (the
  # GUI VM, which sets HandlePowerKey="ignore" under the gui power-manager
  # profile). These must be powered off via givc, not a QMP/ACPI button.
  givcShutdownVms = lib.attrNames (
    filterAttrs (
      _: vm:
      let
        vmConfig = lib.ghaf.vm.getConfig vm;
      in
      vmConfig != null
      && vmConfig.ghaf.services.power-manager.enable
      && vmConfig.ghaf.services.power-manager.gui.enable
    ) config.microvm.vms
  );

  # Every other VM accepts an ACPI power button, so the host shuts it down via
  # QEMU QMP system_powerdown: the guest runs its own unprivileged systemd
  # poweroff (flushing+sealing journald) before QEMU exits. This grants the guest
  # no new privilege and does not depend on the givc admin coordinator.
  qmpShutdownVms = lib.attrNames (
    filterAttrs (
      _: vm:
      let
        vmConfig = lib.ghaf.vm.getConfig vm;
      in
      vmConfig != null
      && vmConfig.microvm.hypervisor == "qemu"
      && !(vmConfig.ghaf.services.power-manager.enable && vmConfig.ghaf.services.power-manager.gui.enable)
    ) config.microvm.vms
  );

  crosvmShutdownVms = lib.attrNames (
    filterAttrs (
      _: vm:
      let
        vmConfig = lib.ghaf.vm.getConfig vm;
      in
      vmConfig != null
      && vmConfig.microvm.hypervisor == "crosvm"
      && !(vmConfig.ghaf.services.power-manager.enable && vmConfig.ghaf.services.power-manager.gui.enable)
    ) config.microvm.vms
  );

  # List of VMs that should run kernel GPU suspend when the host suspends
  gpuSuspendVms = lib.attrNames (
    filterAttrs (
      _n: v:
      let
        vmConfig = lib.ghaf.vm.getConfig v;
      in
      vmConfig != null
      && vmConfig.ghaf.services.power-manager.enable
      && vmConfig.ghaf.services.power-manager.vm.enable
      && vmConfig.ghaf.services.power-manager.gui.enable
      && vmConfig.ghaf.services.power-manager.gui.gpuSuspend
    ) config.microvm.vms
  );
  crosvmGpuSuspendVms = lib.filter (
    vmName:
    let
      vmConfig = lib.ghaf.vm.getConfig config.microvm.vms.${vmName};
    in
    vmConfig != null && vmConfig.microvm.hypervisor == "crosvm"
  ) gpuSuspendVms;
  crosvmGpuResumeCases = concatMapStringsSep "\n" (
    vmName:
    let
      vmConfig = lib.ghaf.vm.getConfig config.microvm.vms.${vmName};
      controlSocket =
        if vmConfig != null && (vmConfig.microvm.socket or null) != null then
          "${config.microvm.stateDir}/${vmName}/${vmConfig.microvm.socket}"
        else
          "";
      crosvmPackage = vmConfig.microvm.crosvm.package;
    in
    ''
      ${lib.escapeShellArg vmName})
        control_socket=${lib.escapeShellArg controlSocket}
        if [ -z "$control_socket" ] || [ ! -S "$control_socket" ]; then
          echo "Crosvm control socket $control_socket does not exist for $vm_name" >&2
        elif ${crosvmPackage}/bin/crosvm --no-syslog resume "$control_socket"; then
          resume_signal_sent=1
        else
          echo "Crosvm resume command failed for $vm_name" >&2
        fi
        ;;
    ''
  ) crosvmGpuSuspendVms;

  # Host suspend actions
  host-suspend-actions = pkgs.writeShellApplication {
    name = "host-suspend-actions";
    runtimeInputs = [
      givc-cli
      pkgs.systemd
      pkgs.coreutils
      pkgs.grpcurl
      pkgs.jq
      pkgs.socat
      deviceManagerPackage
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
              ${givc-cli} start service --vm "$vm_name" suspend.target &
              # Wait until suspend is active
              ${getExe pkgs.wait-for-unit} ${config.ghaf.networking.hosts.admin-vm.ipv4} 9001 \
              "$vm_name" systemd-suspend.service 10 \
              activating start
              ;;
            resume)
              echo "Signaling resume to $vm_name..."
              ${givc-cli} stop service --vm "$vm_name" systemd-suspend.service
              ;;
            *)
              echo "Invalid action: $action"
              echo "Usage: $0 <VM Name> {suspend|resume}"
              exit 1
              ;;
          esac
          ;;

        pci-suspend)
          case "$action" in
            suspend)
              echo "Suspending PCI devices for $vm_name..."
              vhotplugcli pci suspend --vm "$vm_name"

              ;;
            resume)
              echo "Resuming PCI devices for $vm_name..."
              if ! vhotplugcli pci resume --vm "$vm_name"; then
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

        gpu-suspend)
          case "$action" in
            suspend)
              echo "Signaling kernel GPU suspend to $vm_name..."
              ${givc-cli} start service --vm "$vm_name" gpu-suspend.service &
              sleep 1
              ;;
            resume)
              wake_socket="${config.microvm.stateDir}/$vm_name/vm-wake.sock"
              echo "Signaling kernel GPU resume to $vm_name..."
              if [[ " ${lib.concatStringsSep " " crosvmGpuSuspendVms} " == *" $vm_name "* ]]; then
                resume_signal_sent=0
                case "$vm_name" in
                  ${crosvmGpuResumeCases}
                esac

                if [ "$resume_signal_sent" != 1 ]; then
                  echo "Crosvm VM $vm_name will resume after its kernel fallback timeout (${toString cfg.gui.gpuSuspendDuration}s)"
                  sleep ${toString cfg.gui.gpuSuspendDuration}
                fi

                deadline=$((SECONDS + 10))
                resumed=0
                while [ "$SECONDS" -lt "$deadline" ]; do
                  if status_response=$(grpcurl \
                    -cacert /etc/givc/ca-cert.pem \
                    -cert /etc/givc/cert.pem \
                    -key /etc/givc/key.pem \
                    -d "{\"VmName\":\"$vm_name\",\"UnitName\":\"gpu-suspend.service\"}" \
                    '${config.ghaf.networking.hosts.admin-vm.ipv4}:9001' \
                    admin.AdminService.GetUnitStatus 2>/dev/null); then
                    active_state=$(jq -r '.ActiveState // "unknown"' <<<"$status_response")
                    sub_state=$(jq -r '.SubState // "unknown"' <<<"$status_response")
                    if [ "$active_state" = "inactive" ] && [ "$sub_state" = "dead" ]; then
                      resumed=1
                      break
                    fi
                  fi
                  sleep 1
                done
                if [ "$resumed" != 1 ]; then
                  echo "Crosvm VM $vm_name did not confirm GPU resume within 10s" >&2
                  exit 1
                fi
                echo "Crosvm VM $vm_name confirmed GPU resume"

                # Crosvm wakes the guest kernel directly, so the guest's
                # sleep.target is not stopped and its ExecStop-based resume
                # hook does not run automatically as it does with QEMU.
                echo "Running resume actions in $vm_name..."
                if ! ${givc-cli} start service --vm "$vm_name" resume-actions.service; then
                  echo "Failed to start resume actions in Crosvm VM $vm_name" >&2
                  exit 1
                fi
              else
                if [ ! -S "$wake_socket" ]; then
                  echo "Wake socket $wake_socket does not exist for QEMU VM $vm_name" >&2
                  exit 1
                fi
                printf 'resume\n' | socat -u - "UNIX-CONNECT:$wake_socket"
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

  gui-vm-suspend = pkgs.writeShellApplication {
    name = "gui-vm-suspend";
    runtimeInputs = [
      pkgs.systemd
      pkgs.coreutils
      pkgs.gawk
    ];
    text = ''
      restart_logind() {
        systemctl restart systemd-logind || echo "Failed to restart systemd-logind; continuing resume fallback"
        sleep 0.3
        local job_ids
        job_ids=$(systemctl list-jobs --no-legend \
          | awk '$2 == "sleep.target" || $2 == "suspend.target" || $2 == "systemd-suspend.service" { print $1 }' \
          | tr '\n' ' ')
        for id in $job_ids; do
          systemctl cancel "$id" && echo "Cancelled suspend job ID $id" || true
        done
      }

      is_lid_open() {
        local state
        # busctl exits non-zero when logind is crashed or unreachable (exactly the
        # case wait_for_lid_open recovers from). Tolerate that here instead of
        # letting errexit/pipefail abort the whole resume helper before the
        # restart_logind fallback runs; an unknown state is treated as not-open.
        state=$(busctl get-property "org.freedesktop.login1" "/org/freedesktop/login1" \
          "org.freedesktop.login1.Manager" "LidClosed" 2>/dev/null | \
              awk 'NR == 1 { print $2 == "true" ? "closed" : "open" }') || true
        echo "Lid state: ''${state:-unknown}"
        [ "$state" = "open" ]
      }

      wait_for_lid_open() {
        is_lid_open && return 0

        echo "Waiting up to 5 seconds for lid to open..."
        local deadline=$(( SECONDS + 5 ))
        while (( SECONDS < deadline )); do
          sleep 0.5
          if is_lid_open; then
            echo "Lid opened, proceeding with resume"
            return 0
          fi
        done

        echo "Lid still closed after 5 seconds, attempting to restart logind..."
        restart_logind
        if is_lid_open; then
          echo "Lid opened after logind restart"
          return 0
        fi
        echo "Lid still closed after logind restart, proceeding with resume anyway"
      }

      echo "Forwarding suspension to host..."
      ${givc-cli} suspend

      echo "Host resumed from suspension"

      wait_for_lid_open
    '';
  };

  guest-power-actions = pkgs.writeShellApplication {
    name = "guest-power-actions";
    runtimeInputs = [
      pkgs.pci-binder
      pkgs.systemd
    ];
    text = ''
      case "$1" in
        reboot|poweroff)
          # Signal host to power off or reboot the system
          systemd-run --no-block -u "signal-$1-host" \
            -p DefaultDependencies=no -p TimeoutSec=5 \
            -- ${givc-cli} "$1"
          # This is a workaround since givc-cli does not support async requests,
          # and may not return (or return an error) when requesting reboot or shutdown
          ;;
        suspend)
          # Script to unbind PCI devices for suspend
          # For convenience, we pass IDs of all passthrough PCI devices,
          # each guest will automatically determine the correct PCI devices.
          # Boards that resolve passthrough dynamically in vhotplug populate no static ids
          # (hardware-intel-laptop is one), so there the guest detects its own devices.
          pci-binder unbind ${if pciDevices == [ ] then "--auto" else lib.concatStringsSep " " pciDevices}
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

  host-set-mem-sleep = pkgs.writeShellApplication {
    name = "host-set-mem-sleep";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    text = ''
      board_vendor="$(cat /sys/class/dmi/id/board_vendor)"
      board_name="$(cat /sys/class/dmi/id/board_name)"
      current_model="$board_vendor $board_name"
      echo "Checking s2idle for model: $current_model"

      if ! grep -qxF "$current_model" <<'EOF'; then
      ${lib.concatStringsSep "\n" cfg.suspend.s2idleModels}
      EOF
        exit 0
      fi

      if ! grep -qw "s2idle" /sys/power/mem_sleep; then
        echo "s2idle is not supported on this model: $current_model"
        exit 1
      fi

      echo "Enabling s2idle mode"
      printf '%s' "s2idle" > /sys/power/mem_sleep
    '';
  };

  genericSleepConf = {
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  }
  // optionalAttrs (!cfg.suspend.enable) {
    AllowSuspend = "no";
  };

in
{
  _file = ./power.nix;

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

    suspend = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to enable system suspension.

          If disabled, the system will not respond to suspend requests, and all VMs with a
          power management profile enabled are prohibited to perform any suspend action.
        '';
      };

      mode = mkOption {
        type = types.nullOr (
          types.enum [
            "auto"
            "s2idle"
            "shallow"
            "deep"
          ]
        );
        default = null;
        description = ''
          The memory suspend mode to use.

          When set to `auto`, Ghaf does not add the `mem_sleep_default` kernel
          parameter. Instead, a boot-time script enables `s2idle` only for
          models listed in `ghaf.services.power-manager.suspend.s2idleModels`.

          To check which modes are supported, run `cat /sys/power/mem_sleep`.

          More info: https://docs.kernel.org/admin-guide/pm/sleep-states.html
        '';
      };

      extraSuspendCommands = mkOption {
        type = types.str;
        default = "";
        description = ''
          Additional shell commands to execute before the system suspends.
        '';
      };

      extraResumeCommands = mkOption {
        type = types.str;
        default = "";
        description = ''
          Additional shell commands to execute after the system resumes from suspension.
        '';
      };

      s2idleModels = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = literalExpression ''
          [
            "System76 Darter Pro"
          ]
        '';
        description = ''
          List of DMI model identifiers in the format `"<board_vendor> <board_name>"`.

          These are used only when `ghaf.services.power-manager.suspend.mode = "auto"`.
          For matching models, a boot-time script enables `s2idle`.
        '';
      };
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
      gpuSuspend = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether the host should trigger kernel GPU suspend for this VM before host suspend.
        '';
      };
      gpuSuspendDuration = mkOption {
        type = types.ints.positive;
        default = 20;
        description = ''
          Duration in seconds for the kernel GPU suspend pm_test delay.
          This is used as a fallback timeout if the socket wakeup signal is not received.
        '';
      };
      fakeDisplaySuspend = mkOption {
        type = types.bool;
        default = !cfg.gui.gpuSuspend;
        defaultText = literalExpression "!config.ghaf.services.power-manager.gui.gpuSuspend";
        description = ''
          Whether to use ghaf-powercontrol to fake display off and on during GUI suspend and resume.
        '';
      };
    };
    host = {
      enable = mkEnableOption ''
        Host power management profile. This profile manages the host's pre- and post-suspend actions
        to coordinate guest suspend actions and devices.

        Additionally, if a system VM has `ghaf.gracefulShutdown = true`, enabling this host profile
        allows the host to override the VM's default microvm ExecStop logic, starting
        the guest's `poweroff.target` and waiting for the VM process to exit.
      '';
    };
    usbSuspend = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to enable USB device suspend and resume.
        When enabled, all USB devices are detached from VMs on suspend and re-attached on resume.
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

      systemd.sleep.settings.Sleep = genericSleepConf;

      powerManagement = optionalAttrs cfg.vm.enable {
        powerDownCommands = optionalString cfg.vm.pciSuspend ''
          if ! ${getExe' pkgs.systemd "systemctl"} list-jobs | grep -qE 'poweroff.target.*start|reboot.target.*start'; then
            echo "Stopping configured suspend services..."
            ${concatMapStringsSep "\n" (service: ''
              echo "Stopping service ${service}..."
              systemctl stop ${service}
            '') cfg.vm.pciSuspendServices}
            ${optionalString (cfg.suspend.extraSuspendCommands != "") ''
              # config.ghaf.services.power-manager.suspend.extraSuspendCommands
              echo "Executing configured extra suspend commands..."
              ${cfg.suspend.extraSuspendCommands}
            ''}
          fi
        '';
        resumeCommands =
          optionalString cfg.vm.pciSuspend (
            concatMapStringsSep "\n" (service: ''
              echo "Starting service ${service}..."
              systemctl start ${service}
            '') cfg.vm.pciSuspendServices
          )
          # The GUI profile runs these from resume-actions.service below.
          # Running them here too races two copies of every resume hook.
          + optionalString (cfg.suspend.extraResumeCommands != "" && !cfg.gui.enable) ''
            # config.ghaf.services.power-manager.suspend.extraResumeCommands
            ${cfg.suspend.extraResumeCommands}
          '';
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

        # Pre-suspend actions for the VM.
        #
        # `-` because an ExecStartPre failure takes the whole unit down, and losing the
        # guest's fake suspend -- which is what stops its watchdogs firing on resume -- is
        # far worse than a PCI device that did not reach low power.
        ExecStartPre = optionals cfg.vm.pciSuspend [
          "-${getExe guest-power-actions} suspend"
        ];
      };
    })

    # GUI power management profile
    (mkIf cfg.gui.enable {
      # Shutdown displays early before suspend
      powerManagement = {
        powerDownCommands = lib.mkBefore (
          ''
            if ${getExe' pkgs.systemd "systemctl"} list-jobs | grep -qE 'poweroff.target.*start|reboot.target.*start'; then
              _is_shutdown=0
            else
              _is_shutdown=1
              ${optionalString cfg.gui.fakeDisplaySuspend ''
                ${getExe ghaf-powercontrol} fake-turn-off-displays '*'
              ''}
            fi
          ''
          + optionalString (cfg.suspend.extraSuspendCommands != "") ''
            # config.ghaf.services.power-manager.suspend.extraSuspendCommands
            if [ $_is_shutdown -ne 0 ]; then
              ${cfg.suspend.extraSuspendCommands}
            fi
          ''
        );
      };

      # Allow the host power manager to stop the GUI VM gracefully through GIVC.
      # Unlike the other system VMs, GUI VM ignores the ACPI power button and
      # therefore cannot use the host's QMP system_powerdown path.
      givc.sysvm.capabilities.services = optionals (cfg.vm.enable && useGivc) (
        [ "poweroff.target" ]
        ++ optionals cfg.gui.gpuSuspend [
          "gpu-suspend.service"
          "resume-actions.service"
        ]
      );

      # Override systemd actions for suspend, poweroff, and reboot
      systemd.services = optionalAttrs (cfg.vm.enable && useGivc) (
        {
          systemd-suspend.serviceConfig.ExecStart = [
            ""
            "${getExe gui-vm-suspend}"
          ];

          # Intercept reboot or poweroff actions and relay it to the host
          gui-shutdown-interceptor = {
            description = "Ghaf GUI Shutdown Interceptor";
            wantedBy = [
              "shutdown.target"
            ];
            before = [
              "shutdown.target"
            ];
            unitConfig.DefaultDependencies = false;
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${getExe guest-shutdown-interceptor}";
              TimeoutSec = 5;
            };
          };

          resume-actions = {
            description = "Resume Actions";
            # QEMU stops sleep.target on wake, which runs ExecStop below.
            # With Crosvm GPU suspend, the host instead starts this service
            # explicitly after confirming wake. Crosvm without GPU suspend
            # still needs the normal sleep.target lifecycle.
            wantedBy = optionals (!(config.microvm.hypervisor == "crosvm" && cfg.gui.gpuSuspend)) [
              "sleep.target"
            ];
            before = optionals (!(config.microvm.hypervisor == "crosvm" && cfg.gui.gpuSuspend)) [
              "sleep.target"
            ];
            unitConfig = {
              DefaultDependencies = false;
              StopWhenUnneeded = true;
            };
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStop =
                let
                  resumeActions = pkgs.writeShellScriptBin "resume-actions" ''
                    ${optionalString cfg.gui.fakeDisplaySuspend ''
                      ${getExe ghaf-powercontrol} fake-turn-on-displays '*'
                    ''}

                    # config.ghaf.services.power-manager.suspend.extraResumeCommands
                    ${cfg.suspend.extraResumeCommands}
                  '';
                in
                getExe resumeActions;
            };
          };
        }
        // optionalAttrs cfg.gui.gpuSuspend {
          gpu-suspend = {
            description = "GPU suspend for GUI VM";
            serviceConfig = {
              Type = "oneshot";
              ExecStart =
                let
                  guestGpuSuspend = pkgs.writeShellApplication {
                    name = "guest-gpu-suspend";
                    runtimeInputs = [
                      pkgs.coreutils
                    ];
                    text = ''
                      echo "Activating kernel GPU suspend"
                      # Use pm_test_delay as a fallback timeout if the socket wakeup signal is not received
                      echo ${toString cfg.gui.gpuSuspendDuration} > /sys/module/suspend/parameters/pm_test_delay
                      # Limit pm_test suspend/resume to the GPU and serial wakeup device
                      echo 1 > /sys/module/suspend/parameters/pm_test_gpu_only
                      echo devices > /sys/power/pm_test
                      # Enable ttyS1 as the wakeup source used by the host
                      echo enabled > /sys/class/tty/ttyS1/power/wakeup
                      cat /dev/ttyS1 > /dev/null &
                      # Arm wakeup_count so incoming ttyS1 data is treated as a wakeup event
                      wc=$(cat /sys/power/wakeup_count)
                      echo "$wc" > /sys/power/wakeup_count
                      # Enter suspend and wait for the host wakeup signal
                      echo freeze > /sys/power/state
                      echo "GPU resumed"
                      echo 0 > /sys/module/suspend/parameters/pm_test_gpu_only
                    '';
                  };
                in
                getExe guestGpuSuspend;
            };
          };
        }
      );

      # Logind configuration for desktop
      services.logind.settings.Login =
        let
          lidEvent = if cfg.suspend.enable then "suspend" else "lock";
        in
        mkDefault {
          HandleLidSwitch = lidEvent;
          HandleLidSwitchDocked = "ignore";
          # Below keys are usually handled by host anyway
          HandleSuspendKey = "ignore";
          HandleHibernateKey = "ignore";
          HandlePowerKey = "ignore";
          HandlePowerKeyLongPress = "ignore";
          KillUserProcesses = true;
          UserStopDelaySec = 0;
          # Limit delay from inhibitors that leak across suspend/resume cycles
          # May be caused by net.reactivated.Fprint
          # TODO: Investigate root cause
          InhibitDelayMaxSec = 1;
        };
    })

    (optionalAttrs (options ? microvm && options.microvm ? qemu) {
      # Serial device (ttyS1) for wakeup from kernel GPU suspend.
      # `isa-serial` is an x86 ISA device; aarch64 QEMU (virt machine, no ISA bus)
      # rejects it and the VM fails to start, so gate the wake device on x86. On
      # aarch64 the guest resumes via the fallback timeout (see gpuSuspendDuration).
      microvm.qemu.extraArgs =
        mkIf
          (
            cfg.gui.enable
            && cfg.vm.enable
            && cfg.gui.gpuSuspend
            && pkgs.stdenv.hostPlatform.isx86_64
            && config.microvm.hypervisor == "qemu"
          )
          [
            "-chardev"
            "socket,id=wake0,path=vm-wake.sock,server=on,wait=off"
            "-device"
            "isa-serial,chardev=wake0,index=1"
          ];
    })

    (optionalAttrs (options ? microvm && options.microvm ? crosvm) {
      # Crosvm can inject the ACPI wake event directly over its control socket.
      # Keep the guest kernel timer as a fallback if that command is unavailable.
      microvm.crosvm.extraArgs = mkIf (
        cfg.gui.enable
        && cfg.vm.enable
        && cfg.gui.gpuSuspend
        && pkgs.stdenv.hostPlatform.isx86_64
        && config.microvm.hypervisor == "crosvm"
      ) [ "--s2idle" ];
    })

    # Host power management
    (mkIf cfg.host.enable {
      # Host still handles power buttons in most situations
      services.logind.settings.Login = {
        HandleLidSwitch = mkDefault "ignore";
        # Disable accidental poweroff with light touch
        HandlePowerKey = mkDefault "ignore";
      };

      # We can accomplish the same via systemd.sleep.settings.Sleep MemorySleepMode
      # but it seems keyboard wakeup stops functioning with that approach
      boot.kernelParams = optionals (cfg.suspend.mode != null && cfg.suspend.mode != "auto") [
        "mem_sleep_default=${cfg.suspend.mode}"
      ];

      systemd = {
        sleep.settings.Sleep = genericSleepConf;

        targets = optionalAttrs cfg.suspend.enable {
          "pre-sleep-actions" = {
            description = "Target for pre-sleep host actions";
            unitConfig.StopWhenUnneeded = true;
            wantedBy = [ "sleep.target" ];
            partOf = [ "sleep.target" ];
            wants =
              map (vmName: "pre-sleep-poweroff@${vmName}.service") powerOffVms
              ++ map (vmName: "pre-sleep-fake-suspend@${vmName}.service") fakeSuspendVms
              ++ map (vmName: "pre-sleep-pci-suspend@${vmName}.service") pciSuspendVms
              ++ map (vmName: "pre-sleep-gpu-suspend@${vmName}.service") gpuSuspendVms;
          };
          "post-resume-actions" = {
            description = "Target for post-resume host actions";
            unitConfig.StopWhenUnneeded = true;
            wantedBy = [ "sleep.target" ];
            wants =
              map (vmName: "post-resume-poweroff@${vmName}.service") powerOffVms
              ++ map (vmName: "post-resume-fake-suspend@${vmName}.service") fakeSuspendVms
              ++ map (vmName: "post-resume-pci-suspend@${vmName}.service") pciSuspendVms
              ++ map (vmName: "post-resume-gpu-suspend@${vmName}.service") gpuSuspendVms;
          };
        };

        services = mkMerge [
          (optionalAttrs (cfg.suspend.mode == "auto" && cfg.suspend.s2idleModels != [ ]) {
            set-mem-sleep = {
              description = "Automatic s2idle mem_sleep Mode Selection";
              wantedBy = [ "sysinit.target" ];
              before = [ "sysinit.target" ];
              unitConfig = {
                DefaultDependencies = false;
                ConditionPathExists = [
                  "/sys/power/mem_sleep"
                  "/sys/class/dmi/id/board_vendor"
                  "/sys/class/dmi/id/board_name"
                ];
              };
              serviceConfig = {
                Type = "oneshot";
                ExecStart = "+''${getExe host-set-mem-sleep}";
              };
            };
          })
          # suspend/resume action units
          (optionalAttrs cfg.suspend.enable (
            lib.listToAttrs (
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
                      # Reattach PCI before waking guest services so drivers and
                      # NetworkManager never race a still-detached VFIO device.
                      before = optionals (suspendAction == "pci-suspend") [
                        "post-resume-fake-suspend@%i.service"
                      ];
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
                    "gpu-suspend"
                  ]
              )
            )
            // optionalAttrs cfg.usbSuspend {
              pre-sleep-usb = {
                description = "USB suspend actions before sleep";
                partOf = [ "pre-sleep-actions.target" ];
                wantedBy = [ "pre-sleep-actions.target" ];
                before = [ "sleep.target" ];
                serviceConfig = {
                  Type = "oneshot";
                  ExecStart = "${getExe' deviceManagerPackage "vhotplugcli"} usb suspend";
                };
              };

              post-resume-usb = {
                description = "USB resume actions after wakeup";
                partOf = [ "post-resume-actions.target" ];
                wantedBy = [ "post-resume-actions.target" ];
                after = [ "suspend.target" ];
                serviceConfig = {
                  Type = "oneshot";
                  ExecStart = "${getExe' deviceManagerPackage "vhotplugcli"} usb resume";
                };
              };
            }
          ))
          # Override microvm’s default shutdown behavior
          #
          # By default, microvm attempts to shut down the VM by sending a Ctrl+Alt+Del
          # sequence and waiting for a socket disconnect:
          #   https://github.com/microvm-nix/microvm.nix/blob/main/lib/runners/qemu.nix
          #
          # In our setup, this does not work because microvm uses socat to wait for input
          # from stdio, which is /dev/null under systemd. As a result, the command returns
          # immediately, systemd sees the process as still active, and kills it with SIGTERM.
          #
          # We replace ExecStop with custom logic, by VM class, then wait for the
          # QEMU process ($MAINPID) to exit:
          #   - GUI VM (ignores ACPI, relays power events): start poweroff.target via givc.
          #   - every other VM: send QMP system_powerdown so the guest runs its own
          #     ACPI poweroff and flushes/seals journald before QEMU exits.
          # We also shorten TimeoutStopSec from the microvm default (150s) to 30s.
          (mkIf useGivc (
            lib.listToAttrs (
              map (
                vmName:
                nameValuePair "microvm@${vmName}" {
                  serviceConfig = {
                    TimeoutStopSec = "30";
                    ExecStop =
                      let
                        sysvm-stop = pkgs.writeShellScript "sysvm-stop" ''
                          # During switch-to-configuration activation (local nixos-rebuild
                          # switch or the remote ghaf-build-helper path), affected system VMs
                          # may be restarted as part of host service changes. switch-to-
                          # configuration restarts changed units synchronously, one at a time,
                          # so its process is guaranteed to still be alive on this host for the
                          # entire time this ExecStop script blocks that restart -- regardless
                          # of how activation was invoked. Detect that directly instead of
                          # keying off one hardcoded remote-only unit name. Ordinary manual
                          # stops/restarts (no activation in progress) still use graceful
                          # shutdown.
                          jobs=$(${getExe' pkgs.systemd "systemctl"} list-jobs 2>/dev/null || true)
                          if ! echo "$jobs" | grep -qiE '(sleep|suspend|poweroff|reboot|halt)\.target.*start' \
                            && ${getExe' pkgs.procps "pgrep"} -f 'bin/switch-to-configuration (switch|test)' >/dev/null 2>&1; then
                            echo "switch-to-configuration activation in progress, skipping guest poweroff for '${vmName}'"
                            kill -15 $MAINPID 2>/dev/null
                            while kill -0 $MAINPID 2>/dev/null; do
                              sleep 1
                            done
                            exit 0
                          fi

                          # GUI VM ignores the ACPI power button (HandlePowerKey=ignore) and
                          # relays power events via its interceptor, so it cannot be powered off
                          # with a QMP/ACPI button; deliver poweroff.target through givc instead.
                          # The admin coordinator is alive here because admin-vm is shutdownLast.
                          echo "Starting poweroff target for system VM '${vmName}'"
                          ${givc-cli} start service --vm '${vmName}' poweroff.target &

                          echo "Waiting for system VM '${vmName}' with QEMU PID=$MAINPID to stop"
                          while kill -0 $MAINPID 2>/dev/null; do
                            sleep 1
                          done
                          echo "System VM '${vmName}' with QEMU PID=$MAINPID stopped"
                        '';
                      in
                      [
                        # Clear previous microvm ExecStop logic
                        ""
                        # '+' allows the sysvm-stop script to be executed with full privileges
                        "+${sysvm-stop}"
                      ];
                  };
                }
              ) givcShutdownVms
            )
          ))
          # All ACPI-capable VMs: host-side QMP system_powerdown. The guest runs its
          # own unprivileged systemd poweroff (journald flush+seal) before QEMU
          # exits — no SIGTERM-mid-write corruption, no new guest privilege, no
          # admin coordinator dependency.
          (lib.listToAttrs (
            map (
              vmName:
              nameValuePair "microvm@${vmName}" {
                serviceConfig = {
                  TimeoutStopSec = lib.mkDefault "30";
                  ExecStop =
                    let
                      vmConfig = lib.ghaf.vm.getConfig config.microvm.vms.${vmName};
                      qmpSocket =
                        if vmConfig != null && (vmConfig.microvm.socket or null) != null then
                          "${config.microvm.stateDir}/${vmName}/${vmConfig.microvm.socket}"
                        else
                          "";
                      # Half of TimeoutStopSec: how long to wait for the guest to respond to
                      # ACPI before logging that it hasn't, so an eventual SIGKILL from
                      # systemd's stop timeout isn't a silent surprise in the unit's journal.
                      qmpAcpiGraceSec = 15;
                      qmp-stop = pkgs.writeShellScript "qmp-stop" ''
                        # See sysvm-stop for why this checks for a live switch-to-configuration
                        # process instead of one hardcoded remote-only unit name.
                        jobs=$(${getExe' pkgs.systemd "systemctl"} list-jobs 2>/dev/null || true)
                        if ! echo "$jobs" | grep -qiE '(sleep|suspend|poweroff|reboot|halt)\.target.*start' \
                          && ${getExe' pkgs.procps "pgrep"} -f 'bin/switch-to-configuration (switch|test)' >/dev/null 2>&1; then
                          echo "switch-to-configuration activation in progress, SIGTERM '${vmName}'"
                          kill -15 $MAINPID 2>/dev/null
                          while kill -0 $MAINPID 2>/dev/null; do
                            sleep 1
                          done
                          exit 0
                        fi

                        socket='${qmpSocket}'
                        if [ -n "$socket" ] && [ -S "$socket" ]; then
                          # ACPI poweroff via QEMU QMP: the guest does its own clean systemd
                          # shutdown (journald flush+seal) before QEMU exits. A bounded socat
                          # (-t1) avoids microvm's trailing-`cat` /dev/null stdio trap.
                          echo "QMP system_powerdown -> '${vmName}' ($socket)"
                          printf '{"execute":"qmp_capabilities"}\n{"execute":"system_powerdown"}\n' \
                            | ${pkgs.socat}/bin/socat -t1 - "UNIX-CONNECT:$socket" \
                            || echo "WARN: QMP system_powerdown to '${vmName}' failed; relying on stop timeout" >&2
                        else
                          echo "WARN: no QMP socket for '${vmName}' ('$socket'); SIGTERM fallback" >&2
                          kill -15 $MAINPID 2>/dev/null
                        fi

                        echo "Waiting for VM '${vmName}' with QEMU PID=$MAINPID to stop"
                        waited=0
                        acpi_timeout_logged=0
                        while kill -0 $MAINPID 2>/dev/null; do
                          sleep 1
                          waited=$((waited + 1))
                          if [ "$acpi_timeout_logged" = 0 ] && [ "$waited" -ge ${toString qmpAcpiGraceSec} ]; then
                            acpi_timeout_logged=1
                            echo "WARN: guest '${vmName}' has not responded to ACPI poweroff after ''${waited}s; will be forced by stop timeout if it does not exit" >&2
                          fi
                        done
                        echo "VM '${vmName}' with QEMU PID=$MAINPID stopped"
                      '';
                    in
                    [
                      # Clear previous microvm ExecStop logic
                      ""
                      # '+' runs the qmp-stop script with full privileges
                      "+${qmp-stop}"
                    ];
                };
              }
            ) qmpShutdownVms
          ))
          # Crosvm guests use the same ACPI power-button path, delivered through
          # the Crosvm control socket instead of QMP.
          (lib.listToAttrs (
            map (
              vmName:
              nameValuePair "microvm@${vmName}" {
                serviceConfig = {
                  TimeoutStopSec = lib.mkDefault "30";
                  ExecStop =
                    let
                      vmConfig = lib.ghaf.vm.getConfig config.microvm.vms.${vmName};
                      controlSocket =
                        if vmConfig != null && (vmConfig.microvm.socket or null) != null then
                          "${config.microvm.stateDir}/${vmName}/${vmConfig.microvm.socket}"
                        else
                          "";
                      crosvmPackage = vmConfig.microvm.crosvm.package;
                      crosvmAcpiGraceSec = 15;
                      crosvmStopDeadlineSec = 25;
                      crosvm-stop = pkgs.writeShellScript "crosvm-stop" ''
                        set -u
                        pid="''${MAINPID:-}"
                        if [ -z "$pid" ]; then
                          echo "Crosvm '${vmName}' has no MAINPID; nothing to stop"
                          exit 0
                        fi

                        # Keep host activation bounded: switch-to-configuration
                        # restarts changed units synchronously, so graceful guest
                        # shutdown here would serialize up to 25 seconds per VM.
                        jobs=$(${getExe' pkgs.systemd "systemctl"} list-jobs 2>/dev/null || true)
                        if ! echo "$jobs" | grep -qiE '(sleep|suspend|poweroff|reboot|halt)\.target.*start' \
                          && ${getExe' pkgs.procps "pgrep"} -f 'bin/switch-to-configuration (switch|test)' >/dev/null 2>&1; then
                          echo "switch-to-configuration activation in progress, SIGTERM '${vmName}'"
                          kill -15 "$pid" 2>/dev/null || true
                          while kill -0 "$pid" 2>/dev/null; do
                            sleep 1
                          done
                          exit 0
                        fi

                        if [ -n '${controlSocket}' ] && [ -S '${controlSocket}' ]; then
                          echo "Crosvm powerbtn -> '${vmName}' (${controlSocket})"
                          # Use the package from this VM's evaluated configuration
                          # so the control protocol matches the running process.
                          if ! ${crosvmPackage}/bin/crosvm --no-syslog powerbtn '${controlSocket}'; then
                            echo "WARN: Crosvm powerbtn for '${vmName}' failed; sending SIGTERM" >&2
                            kill -15 "$pid" 2>/dev/null || true
                          fi
                        else
                          echo "WARN: no Crosvm control socket for '${vmName}'; SIGTERM fallback" >&2
                          kill -15 "$pid" 2>/dev/null || true
                        fi

                        echo "Waiting for Crosvm '${vmName}' with PID=$pid to stop"
                        waited=0
                        grace_logged=0
                        while kill -0 "$pid" 2>/dev/null; do
                          sleep 1
                          waited=$((waited + 1))
                          if [ "$grace_logged" = 0 ] && [ "$waited" -ge ${toString crosvmAcpiGraceSec} ]; then
                            grace_logged=1
                            echo "WARN: guest '${vmName}' has not stopped after ''${waited}s; systemd will force it at the stop timeout" >&2
                          fi
                          if [ "$waited" -ge ${toString crosvmStopDeadlineSec} ]; then
                            echo "ERROR: Crosvm '${vmName}' with PID=$pid did not stop within ''${waited}s" >&2
                            exit 1
                          fi
                        done
                        echo "Crosvm '${vmName}' with PID=$pid stopped"
                      '';
                    in
                    [
                      ""
                      "+${crosvm-stop}"
                    ];
                };
              }
            ) crosvmShutdownVms
          ))
          # Handle VMs with shutdownLast enabled
          (lib.listToAttrs (
            map
              (
                vmName:
                lib.nameValuePair "microvm@${vmName}" {
                  before = map (n: "microvm@${n}.service") (
                    lib.filter (n: n != vmName) (lib.attrNames config.microvm.vms)
                  );
                  # The shutdown-last VM is the log aggregator (admin-vm): it stops
                  # after every other VM and has the most journal to flush+seal, so
                  # give it more time before the stop timeout SIGKILLs QEMU.
                  serviceConfig.TimeoutStopSec = "60";
                }
              )
              (
                lib.attrNames (
                  lib.filterAttrs (
                    _: vm:
                    let
                      vmConfig = lib.ghaf.vm.getConfig vm;
                    in
                    vmConfig != null && vmConfig.ghaf.shutdownLast
                  ) config.microvm.vms
                )
              )
          ))
        ];
      };
    })
  ]);
}
