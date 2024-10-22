# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
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
    admin = mkOption {
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
    enableAppUser = mkEnableOption "Enable app for user to run applications.";
    appuser = mkOption {
      default = "appuser";
      type = types.str;
      description = ''
        Default user account to run applications.
      '';
    };
    appuserGroups = mkOption {
      default = [ ];
      type = types.listOf types.str;
      description = ''
        Extra groups for the app user.
      '';
    };
  };

  config = mkIf cfg.enable {

    assertions = [
      {
        assertion = !(cfg.enableLoginUser && cfg.enableProxyUser);
        message = "You cannot enable both login and proxy users at the same time";
      }
      {
        assertion = !(cfg.enableLoginUser && cfg.enableAppUser);
        message = "You cannot enable both login and app users at the same time";
      }
      {
        assertion = !(cfg.enableAppUser && cfg.enableProxyUser);
        message = "You cannot enable both app and proxy users at the same time";
      }
    ];

    users = {
      mutableUsers = cfg.enableLoginUser;
      users =
        {
          "${cfg.admin}" = {
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
        }
        // optionalAttrs cfg.enableAppUser {
          "${cfg.appuser}" = {
            isNormalUser = true;
            createHome = true;
            uid = cfg.loginuid;
            extraGroups = cfg.appuserGroups;
          };
        };
      groups =
        {
          "${cfg.admin}" = {
            name = cfg.admin;
            members = [ cfg.admin ];
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
        }
        // optionalAttrs cfg.enableAppUser {
          "${cfg.appuser}" = {
            name = cfg.appuser;
            members = [ cfg.appuser ];
          };
        };
    };

    # to build ghaf as ghaf-user with caches
    nix.settings.trusted-users = mkIf config.ghaf.profiles.debug.enable [ cfg.admin ];

    # Enable userborn
    services.userborn = optionalAttrs (!cfg.enableLoginUser) {
      enable = true;
    };

    # First boot login user setup
    systemd.services.ghaf-loginuser-setup =
      let
        userSetupScript = pkgs.writeShellApplication {
          name = "ghaf-user-setup";
          runtimeInputs = [
            pkgs.su
            pkgs.shadow
            pkgs.coreutils
            pkgs.ncurses
          ];
          text = ''
            clear
            echo -e "\e[1;32;1m Ghaf User Setup \e[0m"
            echo ""
            echo "Create your user account and set your password."
            echo ""

            # Read new user name
            ACCEPTABLE_USER=false
            until $ACCEPTABLE_USER; do
              echo -n "Enter your user name: "
              read -e -r USERNAME
              USERNAME=''${USERNAME//_/}
              USERNAME=''${USERNAME// /_}
              USERNAME=''${USERNAME//[^a-zA-Z0-9_]/}
              USERNAME=''$(echo -n "$USERNAME" | tr '[:upper:]' '[:lower:]')
              if grep -q -w "$USERNAME:" /etc/passwd; then
                echo "User $USERNAME already exists. Please choose another user name."
              else
                ACCEPTABLE_USER=true
              fi
            done

            # Change login user name and home
            usermod -l "$USERNAME" -d /home/"$USERNAME" -m ${cfg.loginuser}
            groupmod -n "$USERNAME" ${cfg.loginuser}
            chown -R "$USERNAME":users /home/"$USERNAME"
            chmod -R 0760 /home/"$USERNAME"

            # Change password
            until passwd "$USERNAME"; do
              echo "Please try again."
            done

            # Create user.lock file
            install -m 000 /dev/null /etc/user.lock

            echo "User $USERNAME created."
            sleep 1
          '';
        };
      in
      optionalAttrs cfg.enableLoginUser {
        description = "First boot setup of login user";
        enable = true;
        requiredBy = [ "multi-user.target" ];
        before = [ "systemd-user-sessions.service" ];
        after = [ "userborn.service" ];
        path = [ userSetupScript ];
        unitConfig.ConditionPathExists = "!/etc/user.lock";
        serviceConfig = {
          Type = "oneshot";
          StandardInput = "tty";
          StandardOutput = "tty";
          StandardError = "tty";
          TTYPath = "/dev/tty1";
          TTYReset = true;
          TTYVHangup = true;
          ExecStart = "${userSetupScript}/bin/ghaf-user-setup";
        };
      };

    systemd.services.ghaf-home-setup =
      let
        homeSetupScript = pkgs.writeShellApplication {
          name = "ghaf-home-setup";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.getent
          ];
          text = ''
            # Change home dir permissions
            USERNAME=$(getent passwd ${toString cfg.loginuid} | cut -d: -f1)
            mv /home/${cfg.loginuser} /home/"$USERNAME"
            chown -R "$USERNAME":users /home/"$USERNAME"
            chmod -R 0760 /home/"$USERNAME"
          '';
        };
      in
      optionalAttrs cfg.enableLoginUser {
        description = "Correct login user home permissions";
        enable = true;
        requiredBy = [ "multi-user.target" ];
        before = [ "greetd.service" ];
        path = [ homeSetupScript ];
        unitConfig.ConditionPathExists = "/etc/user.lock";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${homeSetupScript}/bin/ghaf-home-setup";
        };
      };
  };
}
