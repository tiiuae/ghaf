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
      description = "Admin account name.";
      type = types.str;
      default = "ghaf";
    };
    initialPassword = mkOption {
      description = "Default password for the admin user account.";
      type = types.str;
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
    extraGroups = mkOption {
      description = "Extra groups for the admin user.";
      type = types.listOf types.str;
      default = [ ];
    };
  };

  config = mkIf cfg.enable {

    users = {
      users = {
        "${cfg.name}" = {
          isNormalUser = true;
          inherit (cfg) initialPassword;
          inherit (cfg) initialHashedPassword;
          inherit (cfg) hashedPassword;
          extraGroups =
            [
              "wheel"
              "video"
            ]
            ++ cfg.extraGroups
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
