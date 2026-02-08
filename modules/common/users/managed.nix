# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
    mkOption
    optionals
    types
    ;
  inherit (lib.attrsets) nameValuePair;

  userAccount = types.submodule {
    options = {
      name = mkOption {
        description = "User name";
        type = types.nullOr types.str;
        default = null;
      };
      vms = mkOption {
        description = "List of VMs (or host) the user is enabled in.";
        type = types.listOf types.str;
        default = [ ];
      };
      initialPassword = mkOption {
        description = "Initial password for the admin user account.";
        type = types.nullOr types.str;
        default = null;
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
      createHome = mkOption {
        description = "Create home directory for the user.";
        type = types.bool;
        default = true;
      };
      linger = mkOption {
        description = "Enable lingering for the user.";
        type = types.bool;
        default = false;
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
  _file = ./managed.nix;

  options.ghaf.users = {
    managed = mkOption {
      description = ''
        List of declarativively managed user accounts.

        The ghaf user interface for declarative users has the following options:
        - No enable flag, a specified account is enabled by default
        [mandatory]
        - name: User name
        - vms: List of VMs (or host) the user is enabled in
        [optional]
        - initialPassword: Default password for the user account
        - initialHashedPassword: Initial hashed password for the user account
        - hashedPassword: Hashed password for live updates
        - uid: Optional user identifier (uid). Defaults to null
        - gid: Optional primary group identifier (gid). Defaults to null
        - createHome: Create home directory for the user
        - linger: Enable lingering for the user
        - extraGroups: Extra groups for the user

        These, as any additional user option, may be set through the usual NixOS user options.
      '';
      type = types.listOf userAccount;
      default = [ ];
    };
  };

  config =
    let
      # Filter out applicable accounts for current system
      accounts = lib.filter (acc: (lib.lists.any (name: name == config.system.name) acc.vms)) cfg.managed;
      hasAccounts = accounts != [ ];
    in
    mkIf hasAccounts {

      assertions = [
        {
          assertion =
            (config.system.name == "gui-vm")
            -> (lib.lists.all (
              acc:
              (
                acc.uid != null
                && acc.uid != config.ghaf.users.homedUser.uid
                && acc.uid != config.ghaf.users.admin.uid
              )
            ) accounts);
          message = "Users in the GUI VM must have a non-reserved uid specified.";
        }
      ];

      users = {
        users = builtins.listToAttrs (
          map (
            acc:
            nameValuePair acc.name {
              isNormalUser = true;
              inherit (acc) initialPassword;
              inherit (acc) initialHashedPassword;
              inherit (acc) hashedPassword;
              inherit (acc) createHome;
              inherit (acc) linger;
              inherit (acc) extraGroups;
            }
            // lib.optionalAttrs (acc.uid != null) {
              inherit (acc) uid;
            }
            // lib.optionalAttrs (acc.gid != null) {
              inherit (acc) gid;
            }
          ) accounts
        );
        groups = builtins.listToAttrs (
          map (
            acc:
            optionals (acc.gid == null) (
              nameValuePair acc.name {
                inherit (acc) name;
                members = [ acc.name ];
              }
            )
          ) accounts
        );
      };
    };
}
