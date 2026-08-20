# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.hardware.passthrough.vhotplug;
  managerCfg = config.ghaf.hardware.passthrough.deviceManager;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    getExe
    ;

  defaultVms = lib.attrsets.mapAttrsToList (
    vmName: vmParams:
    let
      vmConfig = lib.ghaf.vm.getConfig vmParams;
    in
    {
      name = vmName;
      type = if vmConfig != null then vmConfig.microvm.hypervisor else "qemu";
      socket = "${config.microvm.stateDir}/${vmName}/${
        if vmConfig != null then vmConfig.microvm.socket else "microvm.sock"
      }";
    }
  ) config.microvm.vms;
  crosvmPciVms = lib.filter (
    vm: vm.type == "crosvm" && lib.any (rule: (rule.targetVm or null) == vm.name) cfg.pciRules
  ) cfg.vms;
  disableRunnerGlobbing = pkgs.writeText "disable-crosvm-runner-globbing" ''
    set -f
  '';
  waitForCrosvmSocket = pkgs.writeShellApplication {
    name = "wait-for-crosvm-socket";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      if [ "$#" -ne 2 ]; then
        echo "Usage: wait-for-crosvm-socket SOCKET MAIN_PID" >&2
        exit 2
      fi

      socket=$1
      main_pid=$2
      while [ ! -S "$socket" ]; do
        if ! kill -0 "$main_pid" 2>/dev/null; then
          echo "Crosvm process $main_pid exited before creating $socket" >&2
          exit 1
        fi
        sleep 0.1
      done
    '';
  };
  managerService =
    if managerCfg.backend == "ghaf-device-manager" then "ghaf-device-manager" else "vhotplug";
in
{
  _file = ./vhotplug.nix;

  options.ghaf.hardware.passthrough.deviceManager = {
    backend = mkOption {
      type = types.enum [
        "vhotplug"
        "ghaf-device-manager"
      ];
      default = "vhotplug";
      description = ''
        Device manager used by this image. Select ghaf-device-manager only
        when every dynamically managed VM uses Crosvm.
      '';
    };

    package = mkOption {
      type = types.package;
      readOnly = true;
      default =
        if managerCfg.backend == "ghaf-device-manager" then pkgs.ghaf-device-manager else pkgs.vhotplug;
      description = "Package providing the selected daemon and the vhotplugcli compatibility command.";
    };
  };

  options.ghaf.hardware.passthrough.vhotplug = {
    enable = mkEnableOption "the hot plugging of USB devices";

    usbRules = mkOption {
      type = types.listOf types.attrs;
      default = [ ];
      description = ''
        List of USB hot plugging rules.
      '';
    };

    pciRules = mkOption {
      type = types.listOf types.attrs;
      default = [ ];
      description = ''
        List of PCI hot plugging rules.
      '';
    };

    evdevRules = mkOption {
      type = types.listOf types.attrs;
      default = [ ];
      description = ''
        List of evdev hot plugging rules.
      '';
    };

    acpiRules = mkOption {
      type = types.listOf types.attrs;
      default = [ ];
      description = ''
        List of ACPI hot plugging rules.
      '';
    };

    vms = mkOption {
      type = types.listOf types.attrs;
      default = defaultVms;
      description = ''
        List of virtual machines.
      '';
    };

    prependUsbRules = mkOption {
      description = ''
        List of extra USB rules to be added to the system. Uses the same format as vhotplug.usbRules,
        and is prepended to the default rules. This is helpful for setting rules where the order of
        USB device detection matters for additional VMs, while still maintaining the default rules.
      '';
      type = types.listOf types.attrs;
      default = [ ];
    };

    postpendUsbRules = mkOption {
      description = ''
        List of extra USB rules to be added to the system. Uses the same format as vhotplug.usbRules,
        and is postpened to the default rules. This is useful for adding rules for additional VMs while
        keeping the ghaf defaults.
      '';
      type = types.listOf types.attrs;
      default = [ ];
    };

    api = {
      enable = mkOption {
        description = ''
          Enable external API.
        '';
        type = types.bool;
        default = true;
      };

      port = lib.mkOption {
        type = lib.types.int;
        default = 2000;
        description = ''
          API port number.
        '';
      };

      transports = lib.mkOption {
        type = lib.types.listOf (
          lib.types.enum [
            "tcp"
            "unix"
            "vsock"
          ]
        );
        default = [
          "vsock"
          "unix"
        ];
        description = ''
          List of supported transports for the API.
        '';
        example = [
          "tcp"
          "unix"
          "vsock"
        ];
      };

      allowedCids = lib.mkOption {
        type = lib.types.listOf lib.types.int;
        default =
          if config.ghaf.networking.hosts ? gui-vm then [ config.ghaf.networking.hosts.gui-vm.cid ] else [ ];
        description = ''
          List of VSOCK CIDs allowed to connect.
        '';
        example = [
          3
          4
          5
        ];
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion =
          managerCfg.backend != "ghaf-device-manager" || lib.all (vm: vm.type == "crosvm") cfg.vms;
        message = "ghaf-device-manager requires every dynamically managed VM to use Crosvm";
      }
    ];

    services.udev.extraRules = ''
      SUBSYSTEM=="usb", GROUP="kvm"
      KERNEL=="event*", GROUP="kvm"
      SUBSYSTEM=="vfio", GROUP="kvm", MODE="0660"
    '';

    environment.etc."vhotplug.conf".text = builtins.toJSON {
      usbPassthrough = cfg.prependUsbRules ++ cfg.usbRules ++ cfg.postpendUsbRules;
      pciPassthrough = cfg.pciRules;
      evdevPassthrough = cfg.evdevRules;
      acpiPassthrough = cfg.acpiRules;

      inherit (cfg) vms;

      general = {
        api = {
          inherit (cfg.api) enable;
          inherit (cfg.api) port;
          inherit (cfg.api) transports;
          inherit (cfg.api) allowedCids;
          unixSocketUser = "microvm";
        };
        modprobe = lib.getExe' pkgs.kmod "modprobe";
        modinfo = lib.getExe' pkgs.kmod "modinfo";
        crosvm = lib.getExe pkgs.crosvm;
        ovmfCode = "${pkgs.OVMF.fd}/FV/OVMF_CODE.fd";
        ovmfVars = "${pkgs.OVMF.fd}/FV/OVMF_VARS.fd";
      };
    };

    systemd.services = {
      vhotplug = mkIf (managerCfg.backend == "vhotplug") {
        enable = true;
        description = "vhotplug";
        wantedBy = [ "multi-user.target" ];
        after = [ "local-fs.target" ];
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "1";
          ExecStart = "${getExe pkgs.vhotplug} -a -c /etc/vhotplug.conf";
        };
        startLimitIntervalSec = 0;
      };

      ghaf-device-manager = mkIf (managerCfg.backend == "ghaf-device-manager") {
        enable = true;
        description = "Ghaf Crosvm device manager";
        wantedBy = [ "multi-user.target" ];
        after = [ "local-fs.target" ];
        conflicts = [ "vhotplug.service" ];
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "1";
          ExecStart = "${getExe managerCfg.package} -a -c /etc/vhotplug.conf";
        };
        startLimitIntervalSec = 0;
      };
    }
    // builtins.listToAttrs (
      map (vm: {
        name = "microvm@${vm.name}";
        value = {
          requires = [ "${managerService}.service" ];
          after = [ "${managerService}.service" ];
          serviceConfig = {
            # Keep the service activating until Crosvm has created its control
            # socket. ExecStartPost runs alongside the runner's volume setup
            # and bounded device discovery, unlike microvm.preStart which runs
            # before both and can expire before Crosvm is launched.
            Type = lib.mkForce "exec";
            TimeoutStartSec = "10min";
            ExecStartPre = lib.mkBefore [
              "${pkgs.coreutils}/bin/rm -f ${lib.escapeShellArg vm.socket}"
            ];
            ExecStartPost = lib.mkBefore [
              "${lib.getExe waitForCrosvmSocket} ${lib.escapeShellArg vm.socket} $MAINPID"
            ];
            # microvm.nix expands extraArgsScript output as shell words. The
            # vhotplug CLI rejects whitespace inside arguments; disabling glob
            # expansion completes the safe one-word-per-argument contract.
            # TODO: remove this process-wide workaround after microvm.nix
            # quotes each generated argument in its Crosvm runner.
            Environment = "BASH_ENV=${disableRunnerGlobbing}";
          };
        };
      }) crosvmPciVms
    );

    environment.systemPackages = [ managerCfg.package ];
  };
}
