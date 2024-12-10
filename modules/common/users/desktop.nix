# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.users;
  inherit (lib)
    mkIf
    types
    mkOption
    mkMerge
    optionalString
    concatStringsSep
    ;

  loginUserAccount = types.submodule {
    options = {
      enable = mkOption {
        description = "Enable user account";
        type = types.bool;
        default = false;
      };
      uid = mkOption {
        description = ''
          Login user identifier (uid). Defaults to 1001.
          This UID is also used by the proxy and app auxiliary users.
        '';
        type = types.int;
        default = 1001;
      };
      extraGroups = mkOption {
        description = "Extra groups for the user.";
        type = types.listOf types.str;
        default = [ ];
      };
      homeSize = mkOption {
        description = ''
          Size of the home directory for the login user in MB (integer).
          The integer size is inherited from the microvm volume size parameter.
        '';
        type = types.int;
        default = 10000;
      };
    };
  };

  auxiliaryAccount = types.submodule {
    options = {
      enable = mkOption {
        description = "Enable auxiliary user account";
        type = types.bool;
        default = false;
      };
      name = mkOption {
        description = "Auxiliary user's name";
        type = types.str;
        default = "";
      };
      extraGroups = mkOption {
        description = "Extra groups for the auxiliary user.";
        type = types.listOf types.str;
        default = [ ];
      };
    };
  };

in
{
  options.ghaf.users = {
    # Main UI user
    loginUser = mkOption {
      description = "Default user account for login user.";
      type = loginUserAccount;
      default = { };
    };
    # Proxy user for dbus
    proxyUser = mkOption {
      description = "Default user account for dbus proxy functionality.";
      type = auxiliaryAccount;
      default = { };
    };
    # App user for running applications
    appUser = mkOption {
      description = "User account to run applications.";
      type = auxiliaryAccount;
      default = { };
    };
  };

  config = mkMerge [
    {
      assertions = [
        {
          assertion = cfg.loginUser.enable -> config.ghaf.systemd.withHomed;
          message = "You cannot enable login user without systemd-homed. Enable homed service in systemd module.";
        }
        {
          assertion = cfg.loginUser.enable -> !cfg.proxyUser.enable;
          message = "You cannot enable both login and proxy users at the same time";
        }
        {
          assertion = cfg.loginUser.enable -> !cfg.appUser.enable;
          message = "You cannot enable both login and app users at the same time";
        }
        {
          assertion = cfg.appUser.enable -> (cfg.appUser.name != "");
          message = "App user name must be defined";
        }
        {
          assertion = cfg.proxyUser.enable -> (cfg.proxyUser.name != "");
          message = "Proxy user name must be defined";
        }
      ];

      users = {
        users = mkMerge [
          (mkIf cfg.proxyUser.enable {
            "proxyuser" = {
              isNormalUser = true;
              createHome = false;
              inherit (cfg.loginUser) uid;
              inherit (cfg.proxyUser) extraGroups;
            };
          })
          (mkIf cfg.appUser.enable {
            "appuser" = {
              isNormalUser = true;
              createHome = true;
              inherit (cfg.loginUser) uid;
              inherit (cfg.appUser) extraGroups;
            };
          })
        ];
        groups = mkMerge [
          (mkIf cfg.proxyUser.enable {
            "proxyuser" = {
              inherit (cfg.proxyUser) name;
              members = [ cfg.proxyUser.name ];
            };
          })
          (mkIf cfg.appUser.enable {
            "appuser" = {
              inherit (cfg.appUser) name;
              members = [ cfg.appUser.name ];
            };
          })
        ];
      };
    }

    # Login user setup with homed
    (mkIf cfg.loginUser.enable {

      # Enable homed service
      services.homed.enable = true;

      # First boot login user setup service
      systemd.services.ghaf-loginuser-setup =
        let
          userSetupScript = pkgs.writeShellApplication {
            name = "ghaf-user-setup";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.ncurses
              pkgs.brightnessctl
            ];
            text = ''
              brightnessctl set 100%
              clear
              echo -e "\e[1;32;1mWelcome to Ghaf \e[0m"
              echo ""
              echo "Start by creating your user account."
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

              echo ""
              echo -n "Enter your full name: "
              read -e -r REALNAME
              REALNAME=''${REALNAME//[^a-zA-Z ]/}
              [[ -n "$REALNAME" ]] || REALNAME="$USERNAME";

              echo ""
              echo "Setting up your user account and creating encrypted home folder after you enter your password."
              echo "This may take a while..."
              echo ""

              # Add login user and home
              homectl create "$USERNAME" \
              --real-name="$REALNAME" \
              --skel=/etc/skel \
              --storage=luks \
              --luks-pbkdf-type=argon2id \
              --enforce-password-policy=true \
              --drop-caches=true \
              --nosuid=true \
              --noexec=true \
              --nodev=true \
              --disk-size=${toString cfg.loginUser.homeSize}M \
              --shell=/run/current-system/sw/bin/bash \
              --uid=${toString cfg.loginUser.uid} \
              --member-of=users${
                optionalString (
                  cfg.loginUser.extraGroups != [ ]
                ) ",${concatStringsSep "," cfg.loginUser.extraGroups}"
              }

              # Lock user creation script
              install -m 000 /dev/null /var/lib/nixos/user.lock

              echo ""
              echo "User $USERNAME created. Starting user session..."
              sleep 1
            '';
          };
        in
        {
          description = "First boot user setup";
          enable = true;
          requiredBy = [ "multi-user.target" ];
          before = [ "systemd-user-sessions.service" ];
          path = [ userSetupScript ];
          unitConfig.ConditionPathExists = "!/var/lib/nixos/user.lock";
          serviceConfig = {
            Type = "oneshot";
            StandardInput = "tty";
            StandardOutput = "tty";
            StandardError = "journal";
            TTYPath = "/dev/tty1";
            TTYReset = true;
            TTYVHangup = true;
            ExecStart = "${userSetupScript}/bin/ghaf-user-setup";
          };
        };
    })
  ];
}
