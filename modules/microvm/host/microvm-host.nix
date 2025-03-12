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
  has_acpi_path = config.ghaf.hardware.definition.audio.acpiPath != null;
in
{
  imports = [
    inputs.impermanence.nixosModules.impermanence
    inputs.self.nixosModules.givc
    ./networking.nix
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

      inotifyPassthrough = mkEnableOption "inotify passthrough" // {
        default = true;
      };
    };
  };

  config = mkMerge [
    # Always set the hostname
    { networking.hostName = lib.mkDefault "ghaf-host"; }
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
        logging.client.enable = config.ghaf.logging.enable;
      };

      services.logind.lidSwitch = "ignore";

      # Create host directories for microvm shares
      systemd.tmpfiles.rules =
        let
          vmRootDirs = map (vm: "d /persist/storagevm/${vm} 0700 root root -") (
            builtins.attrNames config.microvm.vms
          );
          vmsWithXdg = lib.filter (
            vm: lib.hasAttr "xdgitems" vm.config.config.ghaf && vm.config.config.ghaf.xdgitems.enable
          ) (builtins.attrValues config.microvm.vms);
          xdgDirs = lib.flatten (map (vm: vm.config.config.ghaf.xdgitems.xdgHostPaths or [ ]) vmsWithXdg);
          xdgRules = map (path: "D ${path} 0700 ${toString config.ghaf.users.loginUser.uid} users -") xdgDirs;
        in
        [
          "d /persist/common 0755 root root -"
          "d /persist/storagevm/homes 0700 microvm kvm -"
          "d ${config.ghaf.security.sshKeys.waypipeSshPublicKeyDir} 0700 root root -"
        ]
        ++ lib.optionals config.ghaf.givc.enable [
          "d /persist/storagevm/givc 0700 microvm kvm -"
        ]
        ++ lib.optionals config.ghaf.logging.enable [
          "d /persist/storagevm/admin-vm/var/lib/private/alloy 0700 microvm kvm -"
        ]
        # Allow permission to microvm user to read ACPI tables of soundcard mic array
        ++ lib.optionals (config.ghaf.virtualization.microvm.audiovm.enable && has_acpi_path) [
          "f ${config.ghaf.hardware.definition.audio.acpiPath} 0400 microvm kvm -"
        ]
        ++ vmRootDirs
        ++ xdgRules;

      # TODO: remove hardcoded paths
      systemd.services."microvm@audio-vm".serviceConfig =
        lib.optionalAttrs config.ghaf.virtualization.microvm.audiovm.enable
          {
            # The + here is a systemd feature to make the script run as root.
            ExecStopPost = lib.mkIf has_remove_pci_device [
              "+${pkgs.writeShellScript "reload-audio" ''
                # The script makes audio device internal state to reset
                # This fixes issue of audio device getting into some unexpected
                # state when the VM is being shutdown during audio mic recording
                echo "1" > /sys/bus/pci/devices/${config.ghaf.hardware.definition.audio.removePciDevice}/remove
                sleep 0.1
                echo "1" > /sys/bus/pci/rescan
              ''}"
            ];
          };

      # Generate anonymous unique device identifier
      systemd.services.generate-device-id = {
        enable = true;
        description = "Generate device unique id";
        wantedBy = [ "local-fs.target" ];
        after = [ "local-fs.target" ];
        unitConfig.ConditionPathExists = "!/persist/common/device-id";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.writeShellScript "generate-device-id" ''
            # Generate a unique device id for the device
            echo -n "$(od -txC -An -N6 /dev/urandom | tr ' ' - | cut -c 2-)" > /persist/common/device-id
          ''}";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = "1";
        };
      };
    })
    (mkIf cfg.sharedVmDirectory.enable {
      # Create directories required for sharing files with correct permissions.
      systemd.tmpfiles.rules =
        let
          vmDirs = map (
            n:
            "d /persist/storagevm/shared/shares/Unsafe\\x20${n}\\x20share/ 0760 ${toString config.ghaf.users.loginUser.uid} users"
          ) cfg.sharedVmDirectory.vms;
        in
        [
          "d /persist/storagevm/shared 0755 root root"
          "d /persist/storagevm/shared/shares 0760 ${toString config.ghaf.users.loginUser.uid} users"
        ]
        ++ vmDirs;
    })
    (mkIf
      (
        cfg.sharedVmDirectory.enable
        && cfg.sharedVmDirectory.inotifyPassthrough
        && config.ghaf.virtualization.microvm.guivm.enable
      )
      {
        # Enable passthrough of the shared folder inotify events from the host to the GUI VM
        # This is required for the file manager to refresh the shared folder content when it is updated from AppVMs
        systemd.services.vinotify = {
          enable = true;
          description = "vinotify";
          wantedBy = [ "microvms.target" ];
          before = [ "microvms.target" ];
          serviceConfig = {
            Type = "simple";
            Restart = "always";
            RestartSec = "1";
            ExecStart = "${pkgs.vinotify}/bin/vinotify --cid ${toString config.ghaf.networking.hosts.gui-vm.cid} --port 2000 --path /persist/storagevm/shared/shares --mode host";
          };
          startLimitIntervalSec = 0;
        };

        # Receive shared folder inotify events from the host to automatically refresh the file manager
        ghaf.virtualization.microvm.guivm.extraModules = [
          {
            systemd.services.vinotify = {
              enable = true;
              description = "vinotify";
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "simple";
                Restart = "always";
                RestartSec = "1";
                ExecStart = "${pkgs.vinotify}/bin/vinotify --port 2000 --path /Shares --mode guest";
              };
              startLimitIntervalSec = 0;
            };
          }
        ];
      }
    )
    (mkIf (cfg.enable && config.ghaf.profiles.debug.enable) {
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
              rm -r /persist/storagevm/homes/*
              rm -r /persist/storagevm/gui-vm/var/
              echo "All ghaf login user data removed"
            '';
          };
        in
        {
          description = "Remove ghaf login users";
          enable = true;
          path = [ userRemovalScript ];
          unitConfig.ConditionPathExists = "/persist/storagevm/gui-vm/var/lib/nixos/user.lock";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${userRemovalScript}/bin/remove-users";
          };
        };
    })
    (mkIf (cfg.enable && config.services.userborn.enable) {
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
