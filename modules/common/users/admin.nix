# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.users.admin;
  inherit (lib)
    mkEnableOption
    mkIf
    types
    mkOption
    optionals
    ;
in
{
  _file = ./admin.nix;

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
    isNormalUser = mkOption {
      description = "Whether the admin user is a normal user.";
      type = types.bool;
      default = cfg.enableUILogin;
    };
    uid = mkOption {
      description = "User identifier (uid) for the admin account.";
      type = types.int;
      default = if cfg.enableUILogin then 1001 else 901;
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
    enableUILogin = mkEnableOption "admin user login via the graphical login manager";
    createHome = mkOption {
      description = ''
        Boolean value whether to create admin home folder. Defaults to `config.ghaf.users.admin.enableUILogin`.
        A value of 'false' results in home directory set to `/var/empty`, 'true' will create the home directory
        as `/home/<name>`.
      '';
      type = types.bool;
      default = cfg.enableUILogin;
    };
    homeSize = mkOption {
      description = "Size of the admin user's home directory image in megabytes.";
      type = types.int;
      default = 10 * 1024; # 10 GB
    };
    shell = mkOption {
      description = "Login shell for the admin user.";
      type = types.str;
      default = "/run/current-system/sw/bin/bash";
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
          inherit (cfg) isNormalUser;
          isSystemUser = !cfg.isNormalUser;
          inherit (cfg) initialPassword;
          inherit (cfg) initialHashedPassword;
          inherit (cfg) hashedPassword;
          inherit (cfg) uid;
          inherit (cfg) shell;
          inherit (cfg) createHome;
          # home = if cfg.createHome then "/home/${cfg.name}" else "/var/empty";
          group = "${cfg.name}";
          extraGroups = [
            "wheel"
          ]
          ++ cfg.extraGroups
          ++ optionals config.security.tpm2.enable [ "tss" ]
          ++ optionals config.virtualisation.docker.enable [ "docker" ];
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
