# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  pkgs,
  utils,
  ...
}:
let
  inherit (lib)
    types
    mkOption
    mkEnableOption
    mkIf
    ;
  cfg = config.ghaf.storage.encryption;

  partitions =
    if config.ghaf.partitioning.verity.enable then
      {
        persist = rec {
          partConf = config.image.repart.partitions."50-persist".repartConfig;
          device = "/dev/disk/by-partuuid/${partConf.UUID}";
        };
        swap = rec {
          partConf = config.image.repart.partitions."40-swap".repartConfig;
          device = "/dev/disk/by-partuuid/${partConf.UUID}";
        };
      }
    else
      {
        persist = rec {
          partConf = config.disko.devices.disk.disk1.content.partitions.persist;
          inherit (partConf) device;
        };
        swap = rec {
          partConf = config.disko.devices.disk.disk1.content.partitions.swap;
          inherit (partConf) device;
        };
      };
in
{
  options.ghaf.storage.encryption = {
    enable = mkEnableOption "Encryption of the data partition";
    backendType = mkOption {
      description = "The type of device protecting the encryption passphrase";
      type = types.enum [
        "tpm2"
        "fido2"
      ];
      default = "tpm2";
    };
  };

  config = mkIf cfg.enable {
    security.tpm2.enable = true;

    environment.systemPackages =
      with pkgs;
      lib.mkIf config.ghaf.profiles.debug.enable [
        cryptsetup
        tpm2-tools
        parted
        util-linux
        gptfdisk
      ];

    boot.initrd.luks.devices = {
      persist = {
        inherit (partitions.persist) device;
        tryEmptyPassphrase = true;
        crypttabExtraOpts =
          {
            tpm2 = [
              "tpm2-device=auto"
              # Workaround to not enter emergency mode after 1 invalid PIN
              # https://github.com/systemd/systemd/issues/32041
              "tpm2-measure-pcr=yes"
            ];
            fido2 = [ "fido2-device=auto" ];
          }
          .${cfg.backendType};
      };
      swap = {
        inherit (partitions.swap) device;
        tryEmptyPassphrase = true;
        crypttabExtraOpts = [ "tpm2-device=auto" ];
      };
    };

    systemd.services.luks-enroll-tpm =
      let
        enrollOpts =
          {
            tpm2 = "--tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=${
              if config.ghaf.profiles.debug.enable then "no" else "yes"
            }";
            fido2 = "--fido2-device=auto --fido2-with-user-presence=yes --fido2-with-client-pin=yes";
          }
          .${cfg.backendType};
        unitScript = pkgs.writeShellApplication {
          name = "luks-enroll-tpm-unit-script";
          runtimeInputs = with pkgs; [
            gnugrep
            cryptsetup
            plymouth
            tpm2-tools
          ];
          text = ''
            if cryptsetup luksDump ${partitions.persist.device} | grep -E '(systemd-tpm2|systemd-fido2)'; then
              echo 'TPM already enrolled'
              exit 0
            fi
            echo '-- clearing TPM --'
            tpm2_clear
            echo '========== Enrolling TPM/Yubikey for persist partition =========='
            PASSWORD="" systemd-cryptenroll ${enrollOpts} ${partitions.persist.device}
            echo '-- adding recovery key --'
            PASSWORD="" systemd-cryptenroll --recovery ${partitions.persist.device}
            echo '========== Setting up encrypted swap =========='
            PASSWORD="" systemd-cryptenroll --tpm2-device=auto ${partitions.swap.device}
            echo '========== Removing default passphrase =========='
            systemd-cryptenroll --wipe-slot=password ${partitions.persist.device}
            systemd-cryptenroll --wipe-slot=password ${partitions.swap.device}
          '';
        };
      in
      {
        description = "Enroll encrypted partitions to the TPM and/or to a Yubikey";
        unitConfig.DefaultDependencies = "no"; # run before VMs are launched
        wantedBy = [
          "sysinit.target"
        ];
        before = [
          "sysinit.target"
          "shutdown.target"
        ];
        after = [
          "systemd-tpm2-setup.service"
          "nix-store.mount"
        ];
        wants = [
          "systemd-tpm2-setup.service"
          "nix-store.mount"
          "${utils.escapeSystemdPath partitions.persist.device}.device"
          "${utils.escapeSystemdPath partitions.swap.device}.device"
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe unitScript}";
          RemainAfterExit = true;
        };
      };

    systemd.services.extendswap =
      let
        unitScript = pkgs.writeShellApplication {
          name = "extendswap-unit-script";
          runtimeInputs = with pkgs; [
            util-linux
            gawk
            cryptsetup
            parted
          ];
          text = ''
            PARTNUM=$(partx --noheadings --raw ${partitions.swap.device} | awk '{ print $1 }')
            PARENT_DISK=/dev/$(lsblk --nodeps --noheadings -o pkname ${partitions.swap.device})

            swapoff -va
            echo '- +' | sfdisk -f -N "$PARTNUM" "$PARENT_DISK"
            partprobe
            echo | cryptsetup resize swap
            mkswap /dev/mapper/swap
            swapon -va
            touch /persist/.extendswap
          '';
        };
      in
      {
        inherit (config.ghaf.partitioning.verity) enable;
        description = "Extend swap partition to use available free space";
        unitConfig = {
          DefaultDependencies = "no"; # run before VMs are launched
          ConditionPathExists = "!/persist/.extendswap";
        };
        wantedBy = [
          "sysinit.target"
        ];
        before = [
          "sysinit.target"
          config.systemd.services.luks-enroll-tpm.name
          "shutdown.target"
        ];
        conflicts = [
          "shutdown.target"
        ];
        after = [
          "nix-store.mount"
          "persist.mount"
        ];
        wants = [
          "nix-store.mount"
          "dev-mapper-swap.device"
          "persist.mount"
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe unitScript}";
          RemainAfterExit = true;
        };
      };
  };
}
