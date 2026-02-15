# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
in
{
  _file = ./disk-encryption.nix;

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
    partitionDevice = mkOption {
      type = types.str;
      description = "Device path for the partition to encrypt (set by the active partitioning module)";
    };
  };

  config = mkIf (cfg.enable && !cfg.deferred) {
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
      crypted = {
        device = cfg.partitionDevice;
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
            P_DEVPATH=$(readlink -f ${cfg.partitionDevice})
            if cryptsetup luksDump "$P_DEVPATH" | grep -E '(systemd-tpm2|systemd-fido2)'; then
              echo 'TPM already enrolled'
              exit 0
            fi
            echo "========== Enrolling ${
              if cfg.backendType == "tpm2" then "TPM2" else "FIDO2 device"
            } for persist partition =========="
            PASSWORD="" systemd-cryptenroll ${enrollOpts} "$P_DEVPATH"

            echo '-- adding recovery key --'
            PASSWORD="" systemd-cryptenroll --recovery "$P_DEVPATH"

            echo '========== Removing default passphrase =========='
            systemd-cryptenroll --wipe-slot=password "$P_DEVPATH"
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
          "${utils.escapeSystemdPath cfg.partitionDevice}.device"
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe unitScript}";
          RemainAfterExit = true;
        };
      };
  };
}
