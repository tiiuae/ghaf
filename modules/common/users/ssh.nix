# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.users.ssh;
  inherit (lib)
    mkIf
    types
    mkOption
    ;
in
{
  options.ghaf.users.ssh = {
    enable = mkOption {
      description = "Enable the ssh user account. Enabled by default.";
      type = types.bool;
      default = false;
    };
    name = mkOption {
      description = "SSH user account name.";
      type = types.str;
      default = "ssh-user";
    };
    initialPassword = mkOption {
      description = "Default password for the ssh user account.";
      type = types.str;
      default = "ghaf";
    };
    initialHashedPassword = mkOption {
      description = "Initial hashed password for the ssh user account.";
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
          inherit (cfg) name;
          inherit (cfg) initialPassword;
          inherit (cfg) initialHashedPassword;
          inherit (cfg) hashedPassword;
          inherit (cfg) extraGroups;
        };
      };
      groups = {
        "${cfg.name}" = {
          inherit (cfg) name;
          members = [ cfg.name ];
        };
      };
    };
  };
}
