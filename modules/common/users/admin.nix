# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.users.admin;
  inherit (lib)
    mkIf
    types
    mkOption
    optionals
    ;
in
{
  options.ghaf.users.admin = {
    enable = mkOption {
      description = "Enable the admin user account. Enabled by default.";
      type = types.bool;
      default = true;
    };
    name = mkOption {
      description = "Admin account name. Defaults to 'ghaf'.";
      type = types.str;
      default = "ghaf";
    };
    uid = mkOption {
      description = "User identifier (uid) for the admin account.";
      type = types.int;
      default = 1001;
    };
    initialPassword = mkOption {
      description = "Default password for the admin user account.";
      type = types.nullOr types.str;
      default = "ghaf";
    };
    initialHashedPassword = mkOption {
      description = "Initial hashed password for the admin user account.";
      type = types.nullOr types.str;
      default = null;
    };
    hashedPassword = mkOption {
      description = "Hashed password for live updates.";
      type = types.nullOr types.str;
      default = null;
    };
    createHome = mkOption {
      description = ''
        Boolean value whether to create admin home folder. Defaults to false, which
        sets it to '/var/empty'. A value of true will create the home directory as /home/<name>.
      '';
      type = types.bool;
      default = false;
    };
    extraGroups = mkOption {
      description = "Extra groups for the admin user.";
      type = types.listOf types.str;
      default = [ ];
    };
  };

  config = mkIf cfg.enable {

    # Assertions
    assertions = [
      {
        assertion =
          (cfg.initialPassword != null)
          || (cfg.initialHashedPassword != null)
          || (cfg.hashedPassword != null);
        message = ''
          No password set for the admin account. Please set one of the following options:
            - initialPassword
            - initialHashedPassword
            - hashedPassword
          to allow admin login.
        '';
      }
    ];

    users = {
      users = {
        "${cfg.name}" = {
          isNormalUser = true;
          inherit (cfg) initialPassword;
          inherit (cfg) initialHashedPassword;
          inherit (cfg) hashedPassword;
          inherit (cfg) uid;
          inherit (cfg) createHome;
          home = if cfg.createHome then "/home/${cfg.name}" else "/var/empty";
          extraGroups =
            [
              "wheel"
            ]
            ++ cfg.extraGroups
            ++ optionals cfg.createHome [
              "audio"
              "video"
            ]
            ++ optionals config.security.tpm2.enable [ "tss" ]
            ++ optionals config.ghaf.virtualization.docker.daemon.enable [ "docker" ];
        };
      };
      groups = {
        "${cfg.name}" = {
          inherit (cfg) name;
          members = [ cfg.name ];
        };
      };
    };

    # to build ghaf as admin with caches
    nix.settings.trusted-users = mkIf config.ghaf.profiles.debug.enable [ cfg.name ];
  };
}
