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
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    types
    ;

  auxiliaryAccount = types.submodule {
    options = {
      enable = mkEnableOption "auxiliary user account";
      name = mkOption {
        description = "Auxiliary users name.";
        type = types.str;
      };
      uid = mkOption {
        description = "Auxiliary users UID.";
        type = types.int;
        default = 1000;
      };
      extraGroups = mkOption {
        description = "Extra groups for the auxiliary users.";
        type = types.listOf types.str;
        default = [ ];
      };
    };
  };
in
{
  _file = ./auxiliary.nix;

  options.ghaf.users = {
    appUser = mkOption {
      description = "User account for app-vms running applications.";
      type = auxiliaryAccount;
    };
    proxyUser = mkOption {
      description = "User account for system-vms running dbus proxy functionality.";
      type = auxiliaryAccount;
    };
  };

  config = {

    # Auxiliary user names
    ghaf.users.appUser.name = "appuser";
    ghaf.users.proxyUser.name = "proxyuser";

    # Auxiliary user accounts
    users = {
      users = mkMerge [
        (mkIf cfg.appUser.enable {
          "${cfg.appUser.name}" = {
            isNormalUser = true;
            createHome = true;
            linger = true;
            inherit (cfg.appUser) uid;
            inherit (cfg.appUser) extraGroups;
          };
        })
        (mkIf cfg.proxyUser.enable {
          "${cfg.proxyUser.name}" = {
            isNormalUser = true;
            createHome = false;
            inherit (cfg.proxyUser) uid;
            inherit (cfg.proxyUser) extraGroups;
          };
        })
      ];
      groups = mkMerge [
        (mkIf cfg.appUser.enable {
          "${cfg.appUser.name}" = {
            inherit (cfg.appUser) name;
            members = [ cfg.appUser.name ];
          };
        })
        (mkIf cfg.proxyUser.enable {
          "${cfg.proxyUser.name}" = {
            inherit (cfg.proxyUser) name;
            members = [ cfg.proxyUser.name ];
          };
        })
      ];
    };
  };
}
