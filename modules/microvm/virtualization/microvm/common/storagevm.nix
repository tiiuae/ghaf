# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
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
    mkForce
    types
    optionals
    optionalAttrs
    ;
  mountPath = "/guestStorage";
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

        files =
          [
            "/etc/ssh/ssh_host_ed25519_key.pub"
            "/etc/ssh/ssh_host_ed25519_key"
          ]
          # TODO Remove with userborn
          ++ optionals config.ghaf.users.accounts.enableLoginUser [
            "/etc/passwd"
            "/etc/shadow.backup"
            "/etc/group"
            "/etc/etc.lock"
          ];
      }
      { inherit (cfg) directories users files; }
    ];

    # TODO Remove with userborn. Fixes impermanence problems with /etc
    system.activationScripts = optionalAttrs config.ghaf.users.accounts.enableLoginUser {
      "_adjust_before_persist_files" = {
        deps = [
          "createPersistentStorageDirs"
        ];
        text = ''
          if [[ ! -f /guestStorage/etc/etc.lock ]]; then
            cp /etc/passwd /guestStorage/etc && rm /etc/passwd
            cp /etc/group /guestStorage/etc && rm /etc/group
            cp /etc/shadow /guestStorage/etc/shadow.backup
            touch /guestStorage/etc/etc.lock
            echo "copied and removed passwd, shadow, group"
          else
            [[ -f /etc/passwd ]] && rm /etc/passwd
            [[ -f /etc/group ]] && rm /etc/group
            rm /etc/shadow
            cp /guestStorage/etc/shadow.backup /etc/shadow
          fi
        '';
      };
    };

    systemd = optionalAttrs config.ghaf.users.accounts.enableLoginUser {
      paths.etc-shadow = {
        wantedBy = [ "local-fs.target" ];
        after = [ "local-fs.target" ];
        pathConfig = {
          PathChanged = [ "/etc/shadow" ];
          Unit = "etc-shadow.service";
        };
      };
      services.etc-shadow = {
        enable = true;
        wantedBy = [ "local-fs.target" ];
        after = [ "local-fs.target" ];
        script = ''
          ${pkgs.coreutils}/bin/cp /etc/shadow /etc/shadow.backup
          ${pkgs.coreutils}/bin/chown root:shadow /etc/shadow
        '';
      };
    };
  };
}
