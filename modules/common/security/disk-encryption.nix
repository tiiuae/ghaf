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
  inherit (lib) mkEnableOption mkIf;
  cfg = config.ghaf.storage.encryption;

  persistConf = rec {
    partConf = config.image.repart.partitions."50-persist".repartConfig;
    device = "/dev/disk/by-partuuid/${partConf.UUID}";
  };
  swapConf = rec {
    partConf = config.image.repart.partitions."01-swap".repartConfig;
    device = "/dev/disk/by-partuuid/${partConf.UUID}";
  };

in
{
  options.ghaf.storage.encryption = {
    enable = mkEnableOption "Encryption of the data partition";
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
        crypttabExtraOpts = [
          "tpm2-device=auto"
          "fido2-device=auto"
        ];
      };
      swap = {
        inherit (swapConf) device;
        tryEmptyPassphrase = true;
        crypttabExtraOpts = [ "tpm2-device=auto" ];
      };
    };

    systemd.services.luks-enroll-tpm =
      let
        unitScript = pkgs.writeShellApplication {
          name = "luks-enroll-tpm-unit-script";
          runtimeInputs = with pkgs; [
            gnugrep
            cryptsetup
          ];
          text = ''
            if cryptsetup luksDump ${persistConf.device} | grep -E '(systemd-tpm2|systemd-fido2)'; then
              exit 0
            fi
            echo '========== Enrolling TPM for persist partition =========='
            read -r -p 'Choose the type of device to enroll: 1 = TPM2, 2 = FIDO2 (default: TPM2): ' CHOICE
            if [[ "$CHOICE" -eq 2 ]]; then
              systemd-cryptenroll --fido2-device=auto --fido2-with-user-presence=false ${persistConf.device}
            else
              systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=true ${persistConf.device}
            fi
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
  };
}
