# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
# account for the development time login with sudo rights
let
  cfg = config.ghaf.users.accounts;
  inherit (lib)
    mkEnableOption
    mkOption
    optionals
    optionalAttrs
    mkIf
    types
    ;
in
{
  #TODO Extend this to allow definition of multiple users
  options.ghaf.users.accounts = {
    enable = mkOption {
      default = true;
      type = types.bool;
      description = ''
        Enable Ghaf user accounts. Defaults to true.
      '';
    };
    user = mkOption {
      default = "ghaf";
      type = types.str;
      description = ''
        The admin account with sudo rights.
      '';
    };
    initialPassword = mkOption {
      default = "ghaf";
      type = types.str;
      description = ''
        Default password for the admin and login user accounts.
      '';
    };
    enableLoginUser = mkEnableOption "Enable login user setup for UI.";
    loginuser = mkOption {
      default = "user";
      type = types.str;
      description = ''
        Default user account for UI.
      '';
    };
    loginuid = mkOption {
      default = 1001;
      type = types.int;
      description = ''
        Default UID for the login user.
      '';
    };
    # TODO Remove proxy user with ssh functionality
    enableProxyUser = mkEnableOption "Enable proxy for login user.";
    proxyuser = mkOption {
      default = "proxyuser";
      type = types.str;
      description = ''
        Default user account for dbus proxy functionality.
      '';
    };
    proxyuserGroups = mkOption {
      default = [ ];
      type = types.listOf types.str;
      description = ''
        Extra groups for the proxy user.
      '';
    };
  };

  config = mkIf cfg.enable {

    assertions = [
      {
        assertion = !(cfg.enableLoginUser && cfg.enableProxyUser);
        message = "You cannot enable both login and proxy users at the same time";
      }
    ];

    users = {
      mutableUsers = cfg.enableLoginUser;
      users =
        {
          "${cfg.user}" = {
            isNormalUser = true;
            inherit (cfg) initialPassword;
            extraGroups =
              [
                "wheel"
                "video"
              ]
              ++ optionals config.security.tpm2.enable [ "tss" ]
              ++ optionals config.ghaf.virtualization.docker.daemon.enable [ "docker" ];
          };
        }
        // optionalAttrs cfg.enableLoginUser {
          "${cfg.loginuser}" = {
            isNormalUser = true;
            uid = cfg.loginuid;
            inherit (cfg) initialPassword;
            extraGroups = [
              "video"
            ];
          };
        }
        // optionalAttrs cfg.enableProxyUser {
          "${cfg.proxyuser}" = {
            isNormalUser = true;
            createHome = false;
            uid = cfg.loginuid;
            extraGroups = cfg.proxyuserGroups;
          };
        };
      groups =
        {
          "${cfg.user}" = {
            name = cfg.user;
            members = [ cfg.user ];
          };
        }
        // optionalAttrs cfg.enableLoginUser {
          "${cfg.loginuser}" = {
            name = cfg.loginuser;
            members = [ cfg.loginuser ];
          };
        }
        // optionalAttrs cfg.enableProxyUser {
          "${cfg.proxyuser}" = {
            name = cfg.proxyuser;
            members = [ cfg.proxyuser ];
          };
        };
    };

    # to build ghaf as ghaf-user with caches
    nix.settings.trusted-users = mkIf config.ghaf.profiles.debug.enable [ cfg.user ];

    # Enable userborn
    services.userborn =
      {
        enable = true;
      }
      // optionalAttrs cfg.enableLoginUser {
        passwordFilesLocation = "/etc";
      };
  };
}
