# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, config, ... }:
let
  cfg = config.ghaf.storagevm;
  mountPath = "/guestStorage";
in
{
  options.ghaf.storagevm = with lib; {
    enable = mkEnableOption "StorageVM support";

    name = mkOption {
      description = ''
        Name of the corresponding directory on the storage virtual machine.
      '';
      type = types.str;
    };

    directories = mkOption {
      # FIXME: Probably will lead to disgraceful error messages, as we
      # put typechecking on nix impermanence option. But other,
      # proper, ways are much harder.
      type = types.anything;
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
      type = types.anything;
      default = [ ];
      example = [ "/etc/machine-id" ];
      description = ''
        Files to bind mount to persistent storage.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    fileSystems.${mountPath} = {
      neededForBoot = true;
      options = lib.mkForce [
        "rw"
        "nodev"
        "nosuid"
        "noexec"
      ];
    };

    microvm.shares = [
      {
        tag = "hostshare";
        proto = "virtiofs";
        securityModel = "passthrough";
        source = "/storagevm/${cfg.name}";
        mountPoint = mountPath;
      }
    ];

    environment.persistence.${mountPath} = lib.mkMerge [
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
    ];
  };
}
