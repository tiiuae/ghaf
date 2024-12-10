# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.users;
  inherit (lib)
    mkIf
    types
    mkOption
    ;

  userAccount = types.submodule {
    options = {
      enable = mkOption {
        description = "Enable user account";
        type = types.bool;
        default = false;
      };
      name = mkOption {
        description = "User name";
        type = types.str;
        default = "";
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
      uid = mkOption {
        description = "Optional user identifier (uid). Defaults to null.";
        type = types.nullOr types.int;
        default = null;
      };
      gid = mkOption {
        description = "Optional primary group identifier (gid). Defaults to null.";
        type = types.nullOr types.int;
        default = null;
      };
      extraGroups = mkOption {
        description = "Extra groups for the user.";
        type = types.listOf types.str;
        default = [ ];
      };
    };
  };

in
{
  options.ghaf.users = {
    managed = mkOption {
      description = ''
        List of declarativively managed user accounts.

        The ghaf user interface for declarative users has the following options:
        - enable: Enable user account
        - name: User name
        - initialPassword: Default password for the user account.
        - initialHashedPassword: Initial hashed password for the user account.
        - hashedPassword: Hashed password for live updates.
        - uid: Optional user identifier (uid). Defaults to null.
        - gid: Optional primary group identifier (gid). Defaults to null.
        - extraGroups: Extra groups for the user.

        Additional user options may be handled through the NixOS user module.
      '';
      type = types.listOf userAccount;
      default = [ ];
    };
  };

  config = {
    users = {
      users = {
        "${cfg.name}" =
          {
            isNormalUser = true;
            inherit (cfg) initialPassword;
            inherit (cfg) initialHashedPassword;
            inherit (cfg) hashedPassword;
            inherit (cfg) extraGroups;
          }
          // lib.optionalAttrs (cfg.uid != null) {
            inherit (cfg) uid;
          }
          // lib.optionalAttrs (cfg.gid != null) {
            inherit (cfg) gid;
          };
        groups = mkIf (cfg.gid == null) {
          "${cfg.name}" = {
            inherit (cfg) name;
            members = [ cfg.name ];
          };
        };
      };
    };
  };
}
