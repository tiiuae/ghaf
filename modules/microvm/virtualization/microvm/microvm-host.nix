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
      microvm.host.useNotifySockets = true;
      ghaf.systemd = {
        withName = "host-systemd";
        enable = true;
        withAudit = config.ghaf.profiles.debug.enable;
        withPolkit = true;
        withTpm2Tss = pkgs.stdenv.hostPlatform.isx86;
        withRepart = true;
        withFido2 = true;
        withCryptsetup = true;
        withTimesyncd = cfg.networkSupport;
        withNss = cfg.networkSupport;
        withResolved = cfg.networkSupport;
        withSerial = config.ghaf.profiles.debug.enable;
        withDebug = config.ghaf.profiles.debug.enable;
        withHardenedConfigs = true;
      };
      ghaf.givc.host.enable = true;

      # TODO: remove hardcoded paths
      systemd.services."microvm@audio-vm".serviceConfig =
        lib.optionalAttrs config.ghaf.virtualization.microvm.audiovm.enable
          {
            # The + here is a systemd feature to make the script run as root.
            ExecStartPre = [
              "+${pkgs.writeShellScript "ACPI-table-permission" ''
                # The script gives permissionf sot a microvm user
                # to read ACPI tables of soundcaed mic array.
                ${pkgs.coreutils}/bin/chmod 444 /sys/firmware/acpi/tables/NHLT
              ''}"
            ];
            ExecStopPost = [
              "+${pkgs.writeShellScript "reload-audio" ''
                # The script makes audio device internal state to reset
                # This fixes issue of audio device getting into some unexpected
                # state when the VM is being shutdown during audio mic recording
                echo "1" > /sys/bus/pci/devices/0000:00:1f.3/remove
                sleep 0.1
                echo "1" > /sys/bus/pci/devices/0000:00:1f.0/rescan
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
            "d /storagevm/shared/shares/Unsafe\\x20${n}\\x20share/ 0760 ${toString config.ghaf.users.accounts.loginuid} users"
          ) cfg.sharedVmDirectory.vms;
        in
        [
          "d /storagevm/shared 0755 root root"
          "d /storagevm/shared/shares 0760 ${toString config.ghaf.users.accounts.loginuid} users"
        ]
        ++ vmDirs;
    })
  ];
}
