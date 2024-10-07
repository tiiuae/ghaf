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
    enable = mkEnableOption "Default account Setup";
    user = mkOption {
      default = "ghaf";
      type = types.str;
      description = ''
        The admin account with sudo rights.
      '';
    };
    password = mkOption {
      default = "ghaf";
      type = types.str;
      description = ''
        Default password for the admin user.
      '';
    };
    enableLoginUser = mkEnableOption "Enable login user setup for UI.";
    loginuser = mkOption {
      default = "manuel";
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
  };

  config = mkIf cfg.enable {
    users = {
      mutableUsers = cfg.enableLoginUser;
      users =
        {
          "${cfg.user}" = {
            isNormalUser = true;
            inherit (cfg) password;
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
            inherit (cfg) password;
            extraGroups = [
              "video"
            ];
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
        };
    };

    # to build ghaf as ghaf-user with caches
    nix.settings.trusted-users = mkIf config.ghaf.profiles.debug.enable [ cfg.user ];
    #services.userborn.enable = true;
  };
}
