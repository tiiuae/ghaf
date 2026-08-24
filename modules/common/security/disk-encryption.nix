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
    mkMerge
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
    interactiveSetup = mkOption {
      type = types.bool;
      default = true;
      description = "Whether encryption setup requires user interaction (false = debug/automated)";
    };
    # Declared here (not in the deferred partitioning module) because this
    # module reads it and is imported on every target, while the deferred
    # module only ships in the disko bundle.
    deferred = mkOption {
      type = types.bool;
      default = false;
      description = "Apply disk encryption on first boot instead of at image creation";
    };
    deferredModuleLoaded = mkOption {
      type = types.bool;
      default = false;
      internal = true;
      description = ''
        Set by modules/partitioning/deferred-disk-encryption.nix to signal it is
        imported. `deferred` is declared here so every target can read it, but
        the module that acts on it ships only in the disko bundle -- without
        this the two mutually exclusive config blocks would both be inactive and
        the image would silently build with no encryption at all.
      '';
    };
    debugTools = mkOption {
      type = types.bool;
      default = false;
      description = "Install encryption debug tools (cryptsetup, tpm2-tools, etc.)";
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      assertions = [
        {
          assertion = !cfg.deferred || cfg.deferredModuleLoaded;
          message = ''
            ghaf.storage.encryption.deferred is set, but
            modules/partitioning/deferred-disk-encryption.nix is not imported,
            so nothing would perform the encryption and the image would ship
            unencrypted.
          '';
        }
      ];
    })

    (mkIf (cfg.enable && !cfg.deferred) {
      security.tpm2.enable = true;

      environment.systemPackages = lib.mkIf cfg.debugTools [
        pkgs.cryptsetup
        config.ghaf.security.tpm2.tools
        pkgs.parted
        pkgs.util-linux
        pkgs.gptfdisk
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
                if cfg.interactiveSetup then "yes" else "no"
              }";
              fido2 = "--fido2-device=auto --fido2-with-user-presence=yes --fido2-with-client-pin=yes";
            }
            .${cfg.backendType};
          unitScript = pkgs.writeShellApplication {
            name = "luks-enroll-tpm-unit-script";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.cryptsetup
              pkgs.plymouth
              config.ghaf.security.tpm2.tools
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
              # Never print the recovery key to stdout: this unit logs to the
              # journal, which is persisted and may be exported off-device.
              #
              # /run, not /var/lib: the recovery key opens the encrypted volume,
              # so persisting it in cleartext on the unencrypted root would hand
              # it to anyone who takes the disk out. It lives in tmpfs until
              # collected, and is gone at reboot.
              umask 077
              mkdir -p /run/ghaf || echo 'WARNING: could not create /run/ghaf.' >&2
              recovery_key=""
              if ! recovery_key=$(PASSWORD="" systemd-cryptenroll --recovery "$P_DEVPATH"); then
                echo 'WARNING: recovery key enrollment failed; continuing so the default passphrase is still removed.' >&2
              elif [ -z "$recovery_key" ]; then
                echo 'WARNING: recovery key enrollment produced no key; continuing so the default passphrase is still removed.' >&2
              elif ! printf '%s\n' "$recovery_key" > /run/ghaf/luks-recovery-key; then
                echo 'WARNING: could not persist the recovery key to /run/ghaf/luks-recovery-key.' >&2
              else
                echo 'Recovery key written to /run/ghaf/luks-recovery-key (root-only, tmpfs). Collect it before rebooting.'
              fi
              unset recovery_key

              # Unconditional, and last: an empty passphrase left enrolled means a
              # device that boots and looks encrypted but opens with no secret at
              # all. Nothing above may abort before this runs.
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
    })
  ];
}
