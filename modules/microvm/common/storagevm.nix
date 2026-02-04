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
  cfg = config.ghaf.storagevm;
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    mkMerge
    types
    optionals
    ;

  homeImageSize =
    if config.ghaf.users.admin.enable then
      if config.ghaf.users.homedUser.enable then
        config.ghaf.users.admin.homeSize + config.ghaf.users.homedUser.homeSize
      else
        config.ghaf.users.admin.homeSize
    else if config.ghaf.users.homedUser.enable then
      config.ghaf.users.homedUser.homeSize
    else
      200000; # Default to 200 GB
in
{
  _file = ./storagevm.nix;
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
      type = types.attrsOf (
        types.submodule (_: {
          options = {
            directories = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Directories to bind mount for this user.";
            };
          };
        })
      );
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
      default = config.ghaf.logging.enable;
      defaultText = "config.ghaf.logging.enable";
      description = ''
        Whether to preserve `journald` and `audit` logs of the VM. If enabled, it will keep logs
        locally in persistant storage across reboots. This is useful for debugging purposes.
      '';
    };

    maximumSize = mkOption {
      type = types.int;
      default = 10 * 1024;
      description = ''
        Maximum size of the storage area in megabytes.
        This is the size of the storage device as seen by the guest (when running `lsblk` for example).
        The image on the host filesystem is a sparse file and only occupies the space actually used by the VM.
      '';
    };

    mountOptions = mkOption {
      type = types.listOf types.anything;
      default = [
        "rw"
        "nodev"
        "nosuid"
        "noexec"
      ];
      description = ''
        Specify a list of mount options that should be used.
        They define access permissions, performance behavior and security restrictions.
        Common options determine whether the filesystem is read-only or writable, if users can execute binaries,
      '';
    };

    encryption = {
      enable = mkEnableOption "Encryption of the VM storage area on the host filesystem";

      initialDiskSize = mkOption {
        type = types.int;
        default = cfg.maximumSize;
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
        options = cfg.mountOptions;
        noCheck = true;
      };
      virtualisation.fileSystems.${cfg.mountPath}.device = "/dev/vda";

      microvm.volumes = [
        {
          image = "/persist/storagevm/img/${cfg.name}.img";
          size = cfg.maximumSize;
          autoCreate = true;
          mountPoint = cfg.mountPath;
        }
      ];
    })
    (lib.mkIf (cfg.enable && cfg.encryption.enable) (
      ## Config with encryption

      let
        hostImage = "/persist/storagevm/img/${cfg.name}.img";
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
          options =
            cfg.mountOptions
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
                  tpm2_evictcontrol -C owner -c ${tpm.passthrough.rootNVIndex} || true
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
              Restart = "on-failure";
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

      microvm.volumes =
        lib.optionals (config.ghaf.users.homedUser.enable || config.ghaf.users.adUsers.enable)
          [
            {
              image = "/persist/storagevm/homes/${cfg.name}-home.img";
              size = homeImageSize;
              fsType = "ext4";
              mountPoint = "/home";
            }
          ];

      preservation = {
        enable = true;
        preserveAt.${cfg.mountPath} = mkMerge [

          # Standard directories and files
          {
            files = [
              {
                file = "/etc/machine-id";
                inInitrd = true;
                configureParent = true;
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
        ];
      };

      # Ensure machine-id is setup in initrd before parsing /etc
      boot.initrd.systemd.services."systemd-tmpfiles-setup" = {
        unitConfig.RequiresMountsFor = "/sysroot${cfg.mountPath}/etc/machine-id";
        after = [ "sysroot.mount" ];
        before = [ "initrd-parse-etc.service" ];
      };

      # Remove systemd-machine-id-commit service
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
