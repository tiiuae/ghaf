# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
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

  };

  options.virtualisation.fileSystems = mkOption { };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
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
            ++ optionals (config.ghaf.type != "admin-vm") [
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
