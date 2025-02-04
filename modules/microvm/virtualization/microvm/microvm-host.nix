# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.virtualization.microvm-host;
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    mkMerge
    types
    ;

  has_remove_pci_device = config.ghaf.hardware.definition.audio.removePciDevice != null;
  has_rescan_pci_device = config.ghaf.hardware.definition.audio.rescanPciDevice != null;
  has_acpi_path = config.ghaf.hardware.definition.audio.acpiPath != null;
  rescan_pci_device =
    if has_rescan_pci_device then
      config.ghaf.hardware.definition.audio.rescanPciDevice
    else
      config.ghaf.hardware.definition.audio.removePciDevice;

in
{
  imports = [
    inputs.impermanence.nixosModules.impermanence
    inputs.self.nixosModules.givc-host
  ];
  options.ghaf.virtualization.microvm-host = {
    enable = mkEnableOption "MicroVM Host";
    networkSupport = mkEnableOption "Network support services to run host applications.";
    sharedVmDirectory = {
      enable = mkEnableOption "shared directory" // {
        default = true;
      };

      vms = mkOption {
        description = ''
          List of names of virtual machines for which unsafe shared folder will be enabled.
        '';
        type = types.listOf types.str;
        default = [ ];
      };
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      microvm.host.enable = true;
      # microvm.host.useNotifySockets = true;

      ghaf = {
        type = "host";
        systemd = {
          withName = "host-systemd";
          enable = true;
          withAudit = config.ghaf.profiles.debug.enable;
          withPolkit = true;
          withTpm2Tss = pkgs.stdenv.hostPlatform.isx86;
          withRepart = true;
          withFido2 = true;
          withCryptsetup = true;
          withLocaled = true;
          withTimesyncd = cfg.networkSupport;
          withNss = cfg.networkSupport;
          withResolved = cfg.networkSupport;
          withSerial = config.ghaf.profiles.debug.enable;
          withDebug = config.ghaf.profiles.debug.enable;
          withHardenedConfigs = true;
        };
        givc.host.enable = true;
        development.nix-setup.automatic-gc.enable = config.ghaf.development.nix-setup.enable;
      };

      services.logind.lidSwitch = "ignore";

      # Create host directories for microvm shares
      systemd.tmpfiles.rules =
        let
          vmRootDirs = map (vm: "d /storagevm/${vm} 0700 root root -") (
            builtins.attrNames config.microvm.vms
          );
        in
        [
          "d /storagevm/homes 0700 microvm kvm -"
          "d ${config.ghaf.security.sshKeys.waypipeSshPublicKeyDir} 0700 root root -"
        ]
        ++ lib.optionals config.ghaf.givc.enable [
          "d /storagevm/givc 0700 microvm kvm -"
        ]
        ++ vmRootDirs;

      # TODO: remove hardcoded paths
      systemd.services."microvm@audio-vm".serviceConfig =
        lib.optionalAttrs config.ghaf.virtualization.microvm.audiovm.enable
          {
            # The + here is a systemd feature to make the script run as root.
            ExecStartPre = lib.mkIf has_acpi_path [
              "+${pkgs.writeShellScript "ACPI-table-permission" ''
                # The script gives permissionf sot a microvm user
                # to read ACPI tables of soundcaed mic array.
                ${pkgs.coreutils}/bin/chmod 444 ${config.ghaf.hardware.definition.audio.acpiPath}
              ''}"
            ];
            ExecStopPost = lib.mkIf has_remove_pci_device [
              "+${pkgs.writeShellScript "reload-audio" ''
                # The script makes audio device internal state to reset
                # This fixes issue of audio device getting into some unexpected
                # state when the VM is being shutdown during audio mic recording
                echo "1" > ${config.ghaf.hardware.definition.audio.removePciDevice}
                sleep 0.1
                echo "1" > ${rescan_pci_device}
              ''}"
            ];
          };
    })
    (mkIf cfg.sharedVmDirectory.enable {
      ghaf.virtualization.microvm.guivm.extraModules = [ (import ./common/shared-directory.nix "") ];

      # Create directories required for sharing files with correct permissions.
      systemd.tmpfiles.rules =
        let
          vmDirs = map (
            n:
            "d /storagevm/shared/shares/Unsafe\\x20${n}\\x20share/ 0760 ${toString config.ghaf.users.loginUser.uid} users"
          ) cfg.sharedVmDirectory.vms;
        in
        [
          "d /storagevm/shared 0755 root root"
          "d /storagevm/shared/shares 0760 ${toString config.ghaf.users.loginUser.uid} users"
        ]
        ++ vmDirs;
    })
    (mkIf config.ghaf.profiles.debug.enable {
      # Host service to remove user
      systemd.services.remove-users =
        let
          userRemovalScript = pkgs.writeShellApplication {
            name = "remove-users";
            runtimeInputs = [
              pkgs.coreutils
            ];
            text = ''
              echo "Removing ghaf login user data"
              rm -r /storagevm/homes/*
              rm -r /storagevm/gui-vm/var/
              echo "All ghaf login user data removed"
            '';
          };
        in
        {
          description = "Remove ghaf login users";
          enable = true;
          path = [ userRemovalScript ];
          unitConfig.ConditionPathExists = "/storagevm/gui-vm/var/lib/nixos/user.lock";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${userRemovalScript}/bin/remove-users";
          };
        };
    })
    (mkIf config.services.userborn.enable {
      system.activationScripts.microvm-host = lib.mkForce "";
      systemd.services."microvm-host-startup" =
        let
          microVmStartupScript = pkgs.writeShellApplication {
            name = "microvm-host-startup";
            runtimeInputs = [
              pkgs.coreutils
            ];
            text = ''
              mkdir -p ${config.microvm.stateDir}
              chown microvm:kvm ${config.microvm.stateDir}
              chmod g+w ${config.microvm.stateDir}
            '';
          };
        in
        {
          enable = true;
          description = "MicroVM host startup service";
          wantedBy = [ "userborn.service" ];
          after = [ "userborn.service" ];
          unitConfig.ConditionPathExists = "!${config.microvm.stateDir}";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${microVmStartupScript}/bin/microvm-host-startup";
          };
        };
    })
  ];
}
