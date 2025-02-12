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
      # FIXME: Probably will lead to disgraceful error messages, as we
      # put typechecking on nix impermanence option. But other,
      # proper, ways are much harder.
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

  };

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
      };
      virtualisation.fileSystems.${cfg.mountPath}.device = "/dev/vda";

      microvm.shares = [
        {
          tag = "hostshare";
          proto = "virtiofs";
          securityModel = "passthrough";
          source = "/storagevm/${cfg.name}";
          mountPoint = cfg.mountPath;
        }
      ];

      microvm.volumes = lib.optionals config.ghaf.users.loginUser.enable [
        {
          image = "/storagevm/homes/${cfg.name}-home.img";
          size = builtins.floor (config.ghaf.users.loginUser.homeSize * 1.15);
          fsType = "ext4";
          mountPoint = "/home";
        }
      ];

      environment.persistence.${cfg.mountPath} = mkMerge [
        {
          hideMounts = true;
          directories = [
            "/var/lib/nixos"
          ];
          files = [
            "/etc/ssh/ssh_host_ed25519_key.pub"
            "/etc/ssh/ssh_host_ed25519_key"
          ];
        }
        { inherit (cfg) directories users files; }
        (mkIf config.ghaf.users.loginUser.enable {
          directories = [
            "/var/lib/systemd/home"
          ];
        })
      ];

      # Workaround, fixes homed machine-id dependency
      environment.etc = lib.optionalAttrs config.ghaf.users.loginUser.enable {
        machine-id.text = "d8dee68f8d334c79ac8f8229921e0b25";
      };
    })
    (lib.mkIf (config.ghaf.givc.enable && config.ghaf.givc.enableTls) {
      virtualisation.fileSystems.${cfg.mountPath} = {
        device = "/dev/disk/by-label/givc-${cfg.name}";
      };
      microvm.volumes = [
        {
          image = "/storagevm/givc/${cfg.name}.img";
          readOnly = true;
          autoCreate = false;
          fsType = "ext4";
          mountPoint = "/etc/givc";
        }
      ];
    })
  ];
}
