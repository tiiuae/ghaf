# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.ghaf.storagevm;
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    mkMerge
    types
    optionals
    ;
in
{
  options.ghaf.storagevm = {
    enable = mkEnableOption "StorageVM support";

    name = mkOption {
      description = ''
        Name of the corresponding directory on the storage virtual machine.
      '';
      type = types.str;
    };

    mountPath = mkOption {
      description = ''
        Mount path for the storage virtual machine.
      '';
      type = types.str;
      default = "/guestStorage";
    };

    directories = mkOption {
      type = types.listOf types.anything;
      default = [ ];
      example = [
        "/var/lib/nixos"
        "/var/log"
        "/var/lib/bluetooth"
        "/var/lib/systemd/coredump"
      ];
      description = ''
        Directories to bind mount to persistent storage.
      '';
    };

    users = mkOption {
      type = types.anything;
      default = { };
      example = {
        "user".directories = [
          "Downloads"
          "Music"
          "Pictures"
          "Documents"
          "Videos"
        ];
      };
      description = ''
        User-specific directories to bind mount to persistent storage.
      '';
    };

    files = mkOption {
      type = types.listOf types.anything;
      default = [ ];
      example = [ "/etc/machine-id" ];
      description = ''
        Files to bind mount to persistent storage.
      '';
    };

    preserveLogs = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to preserve `journald` and `audit` logs of the VM. If enabled, it will keep logs
        locally in persistant storage across reboots. This is useful for debugging purposes.
      '';
    };

    encryption = {
      enable = mkEnableOption "Encryption of the VM storage area on the host filesystem";

      initialDiskSize = mkOption {
        type = types.int;
        default = 10 * 1024;
        description = ''
          Size of the persistent disk image in megabytes.
          This is the size of the storage device as seen by the guest (when running `lsblk` for example).
          The image on the host filesystem is a sparse file and only occupies the space actually used by the VM.
        '';
      };

      pcrs = mkOption {
        type = types.str;
        description = ''
          List of PCR registers to measure for the guestStorage partition.
          For supported syntax see the --tpm2-pcrs flag description in {manpage}`systemd-cryptenroll(1)`.
        '';
        default = "15";
        example = "7+11+14";
      };

      keepDefaultPassword = mkOption {
        type = types.bool;
        description = ''
          Whether to keep the default password (empty string) that unlocks the VM storage partition.
          Useful for debugging or to recover guest data from the host.
        '';
        default = false;
      };

      serial = mkOption {
        type = types.str;
        default = "vmdata";
        internal = true;
      };

      luksDevice = mkOption {
        type = types.str;
        default = "vmdata";
        internal = true;
      };
    };
  };

  options.virtualisation.fileSystems = mkOption { };

  config = lib.mkMerge [
    (lib.mkIf (cfg.enable && !cfg.encryption.enable) {
      ## Config without encryption

      fileSystems.${cfg.mountPath} = {
        neededForBoot = true;
        options = [
          "rw"
          "nodev"
          "nosuid"
          "noexec"
        ];
        noCheck = true;
      };
      virtualisation.fileSystems.${cfg.mountPath}.device = "/dev/vda";

      microvm.shares = [
        {
          tag = "hostshare";
          proto = "virtiofs";
          securityModel = "passthrough";
          source = "/persist/storagevm/${cfg.name}";
          mountPoint = cfg.mountPath;
        }
      ];
    })
    (lib.mkIf (cfg.enable && cfg.encryption.enable) (
      ## Config with encryption

      let
        hostImage = "/persist/storagevm_enc/${cfg.name}.img";
        drivePath = "/dev/disk/by-id/virtio-${cfg.encryption.serial}";
      in
      {
        assertions = [
          {
            # Revisit when user password is involved in decryption; TPM can be optional
            assertion =
              config.ghaf.virtualization.microvm.tpm.passthrough.enable
              || config.ghaf.virtualization.microvm.tpm.emulated.enable;
            message = "VM must have access to a TPM to enable storage encryption";
          }
        ];

        microvm.volumes = [
          {
            image = hostImage;
            inherit (cfg.encryption) serial;
            autoCreate = false;
            mountPoint = null;
          }
        ];

        boot.initrd.luks.devices = {
          ${cfg.encryption.luksDevice} = {
            device = drivePath;
            crypttabExtraOpts = [ "tpm2-device=auto" ];
            tryEmptyPassphrase = true;
          };
        };

        ghaf.systemd = {
          withCryptsetup = true;
          withTpm2Tss = true;
          withBootloader = true;
          withOpenSSL = true;
        };

        fileSystems.${cfg.mountPath} = {
          device = "/dev/mapper/${cfg.encryption.luksDevice}";
          fsType = "ext4";
          neededForBoot = true;
          options = [
            "rw"
            "nodev"
            "nosuid"
            "noexec"
          ]
          ++ lib.optionals config.ghaf.profiles.debug.enable [
            "nofail"
          ];
        };

        environment.systemPackages = lib.mkIf config.ghaf.profiles.debug.enable [
          pkgs.util-linux
          pkgs.cryptsetup
        ];

        systemd.services.storagevm-enroll =
          let
            drivePath = "/dev/disk/by-id/virtio-${cfg.encryption.serial}";
            inherit (config.ghaf.virtualization.microvm) tpm;

            enrollStorageScript = pkgs.writeShellApplication {
              name = "storagevm-enroll-script";
              runtimeInputs = with pkgs; [
                util-linux
                tpm2-tools
                cryptsetup
              ];
              text = ''
                set -x
                if cryptsetup luksDump ${drivePath} | grep 'systemd-tpm2'; then
                  echo 'TPM already enrolled'
                  exit 0
                fi
                ${lib.optionalString tpm.passthrough.enable ''
                  tpm2_createprimary -C owner -c storage.ctx
                  tpm2_evictcontrol -C owner -c storage.ctx ${tpm.passthrough.rootNVIndex}
                ''}
                # temporary file to pass an empty passphrase to cryptenroll
                echo -n > temp_keyfile
                chmod 600 temp_keyfile
                systemd-cryptenroll --unlock-key-file=temp_keyfile \
                  --tpm2-device=/dev/tpm0 --tpm2-pcrs="${cfg.encryption.pcrs}" \
                  ${lib.optionalString tpm.passthrough.enable "--tpm2-seal-key-handle=${tpm.passthrough.rootNVIndex}"} "${drivePath}"
                rm temp_keyfile
                ${lib.optionalString (!cfg.encryption.keepDefaultPassword) ''
                  echo 'Wiping password slot'
                  systemd-cryptenroll --wipe-slot=password "${drivePath}"
                ''}
              '';
            };
          in
          {
            description = "Enroll the LUKS storagevm image to TPM";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = lib.getExe enrollStorageScript;
              WorkingDirectory = "/tmp";
              ProtectSystem = "strict";
              ReadWritePaths = "/run";
              PrivateTmp = true;
            };
            requires = [
              "${utils.escapeSystemdPath drivePath}.device"
            ];
            wantedBy = [ "multi-user.target" ];
          };
      }
    ))
    (lib.mkIf cfg.enable {
      ## Common config

      microvm.volumes = lib.optionals config.ghaf.users.loginUser.enable [
        {
          image = "/persist/storagevm/homes/${cfg.name}-home.img";
          size = builtins.floor (config.ghaf.users.loginUser.homeSize * 1.15);
          fsType = "btrfs";
          mountPoint = "/home";
        }
      ];

      preservation = {
        enable = true;
        preserveAt.${cfg.mountPath} = mkMerge [

          # Standard directories and files
          {
            directories = [
              "/var/lib/nixos"
            ];
            files = [
              {
                file = "/etc/machine-id";
                inInitrd = true;
              }
            ];
          }

          # User-specific directories and files
          { inherit (cfg) directories users files; }

          # Optional log preservation
          (mkIf cfg.preserveLogs {
            directories = [
              "/var/log/journal"
            ]
            ++ optionals (!config.ghaf.logging.server.enable) [
              "/var/lib/private/alloy"
            ]
            ++ optionals config.security.auditd.enable [
              "/var/log/audit"
            ];
          })

          # Optional files for ssh
          (mkIf config.services.sshd.enable {
            files = [
              {
                file = "/etc/ssh/ssh_host_ed25519_key";
                how = "symlink";
                configureParent = true;
              }
              {
                file = "/etc/ssh/ssh_host_ed25519_key.pub";
                how = "symlink";
                configureParent = true;
              }
            ];
          })

          # Optional directories for systemd home
          (mkIf config.ghaf.users.loginUser.enable {
            directories = [
              "/var/lib/systemd/home"
            ];
          })
        ];
      };

      # Remove systemd machine-id commit service
      systemd.suppressedSystemUnits = [ "systemd-machine-id-commit.service" ];
    })
    (lib.mkIf (config.ghaf.givc.enable && config.ghaf.givc.enableTls) {
      virtualisation.fileSystems.${cfg.mountPath} = {
        device = "/dev/disk/by-label/givc-${cfg.name}";
      };
      microvm.volumes = [
        {
          image = "/persist/storagevm/givc/${cfg.name}.img";
          readOnly = true;
          autoCreate = false;
          fsType = "ext4";
          mountPoint = "/etc/givc";
        }
      ];
    })
  ];
}
