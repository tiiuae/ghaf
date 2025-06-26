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

  persistConf = rec {
    partConf = config.image.repart.partitions."50-persist".repartConfig;
    device = "/dev/disk/by-partuuid/${partConf.UUID}";
  };
  swapConf = rec {
    partConf = config.image.repart.partitions."40-swap".repartConfig;
    device = "/dev/disk/by-partuuid/${partConf.UUID}";
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
        inherit (persistConf) device;
        tryEmptyPassphrase = true;
        crypttabExtraOpts =
          {
            tpm2 = [ "tpm2-device=auto" ];
            fido2 = [ "fido2-device=auto" ];
          }
          .${cfg.backendType};
      };
      swap = {
        inherit (swapConf) device;
        tryEmptyPassphrase = true;
        crypttabExtraOpts = [ "tpm2-device=auto" ];
      };
    };

    systemd.services.luks-enroll-tpm =
      let
        enrollOpts =
          {
            tpm2 = "--tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes";
            fido2 = "--fido2-device=auto --fido2-with-user-presence=no --fido2-with-client-pin=no";
          }
          .${cfg.backendType};
        unitScript = pkgs.writeShellApplication {
          name = "luks-enroll-tpm-unit-script";
          runtimeInputs = with pkgs; [
            gnugrep
            cryptsetup
            plymouth
          ];
          text = ''
            if cryptsetup luksDump ${persistConf.device} | grep -E '(systemd-tpm2|systemd-fido2)'; then
              exit 0
            fi
            plymouth quit
            echo '========== Enrolling TPM/Yubikey for persist partition =========='
            systemd-cryptenroll ${enrollOpts} ${persistConf.device}
            echo '-- adding recovery key --'
            systemd-cryptenroll --recovery ${persistConf.device}
            echo '========== Setting up encrypted swap =========='
            systemd-cryptenroll --tpm2-device=auto ${swapConf.device}
            echo '========== Removing default passphrase =========='
            systemd-cryptenroll --wipe-slot=password ${persistConf.device}
            systemd-cryptenroll --wipe-slot=password ${swapConf.device}
            read -r -s -p 'All done. Press Enter to continue'
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
          "${utils.escapeSystemdPath persistConf.device}.device"
          "${utils.escapeSystemdPath swapConf.device}.device"
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe unitScript}";
          RemainAfterExit = true;
          StandardOutput = "tty";
          StandardInput = "tty";
          TTYPath = "/dev/tty1";
          TTYReset = "yes";
          TTYVHangup = "yes";
          TTYVTDisallocate = "yes";
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
            PARTNUM=$(partx --noheadings --raw ${swapConf.device} | awk '{ print $1 }')
            PARENT_DISK=/dev/$(lsblk --nodeps --noheadings -o pkname ${swapConf.device})

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
        description = "Extend swap partition to use available free space";
        unitConfig = {
          DefaultDependencies = "no"; # run before VMs are launched
          ConditionPathExists = "!/persist/.extendswap";
        };
        wantedBy = [
          "sysinit.target"
          config.systemd.services.luks-enroll-tpm.name
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
