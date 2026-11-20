# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.orin.diskEncryption;
  selector = import ./select-boot-storage.nix {
    inherit pkgs;
    inherit (cfg) luksUuid;
  };
  cryptUnit = "systemd-cryptsetup@${cfg.mapperName}";
  mountEfivars = pkgs.writeShellScript "mount-boot-efivars" ''
    ${pkgs.util-linux}/bin/mountpoint -q /sys/firmware/efi/efivars ||
      ${pkgs.util-linux}/bin/mount -t efivarfs -o nosuid,nodev,noexec efivarfs /sys/firmware/efi/efivars
  '';
in
{
  config = lib.mkIf (config.ghaf.partitioning.verity.enable && cfg.enable) {
    fileSystems."/boot".device = lib.mkForce "/dev/disk/ghaf-esp";
    boot.initrd = {
      kernelModules = [ "efivarfs" ];
      availableKernelModules = [
        "usb_storage"
        "uas"
        "sd_mod"
      ];
      luks.devices.${cfg.mapperName}.device = lib.mkForce "/dev/disk/ghaf-root";
      systemd.storePaths = [
        selector
        mountEfivars
        pkgs.coreutils
        pkgs.util-linux
        pkgs.systemd
      ];
      systemd.services = {
        ghaf-select-boot-storage = {
          description = "Select the encrypted APP on the boot loader's disk";
          wantedBy = [ "initrd.target" ];
          after = [
            "systemd-modules-load.service"
            "systemd-udev-trigger.service"
          ];
          before = [
            "pre-disk-unique-key.service"
            "${cryptUnit}.service"
          ];
          unitConfig = {
            DefaultDependencies = false;
            IgnoreOnIsolate = true;
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            # systemd treats efivarfs as an API filesystem and rejects mount units for it.
            ExecStartPre = mountEfivars;
            ExecStart = lib.getExe selector;
          };
        };
        pre-disk-unique-key = {
          wantedBy = [ "initrd.target" ];
          requires = [ "ghaf-select-boot-storage.service" ];
          after = [ "ghaf-select-boot-storage.service" ];
          # Keep cryptsetup's required services alive across the initrd handoff.
          unitConfig.IgnoreOnIsolate = true;
        };
        ${cryptUnit} = {
          overrideStrategy = "asDropin";
          requires = [ "pre-disk-unique-key.service" ];
          after = [ "pre-disk-unique-key.service" ];
        };
      };
    };
  };
}
