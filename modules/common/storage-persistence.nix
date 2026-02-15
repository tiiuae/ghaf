# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Storage persistence option declarations.
#
# These options are declared in the common bundle so that modules which
# contribute persistent directories/files can do so without requiring
# the microvm bundle. The actual implementation lives in
# modules/microvm/common/storagevm.nix, which provides the config blocks.
{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkOption
    types
    ;
in
{
  _file = ./storage-persistence.nix;

  options.ghaf.storagevm = {
    enable = mkEnableOption "StorageVM support";

    name = mkOption {
      description = ''
        Name of the corresponding directory on the storage virtual machine.
      '';
      type = types.str;
      default = "";
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
        default = config.ghaf.storagevm.maximumSize;
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

      keepDefaultPassword = mkEnableOption "keeping the default password (empty string) that unlocks the VM storage partition";

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
}
