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
    mkEnableOption
    optionalString
    optionalAttrs
    concatStringsSep
    ;

  homedUserAccount = types.submodule {
    options = {
      enable = mkEnableOption "a single homed login user account";
      uid = mkOption {
        description = "Login user identifier (uid). Defaults to 1000 for compatibility.";
        type = types.int;
        default = 1000;
      };
      extraGroups = mkOption {
        description = "Extra groups for the login user.";
        type = types.listOf types.str;
        default = [
          "audio"
          "video"
        ];
      };
      homeSize = mkOption {
        description = ''
          Size of the home directory for the login user in MB (integer).
          The integer size is inherited from the microvm volume size parameter.
          Defaults to 800 GB (800000 MB).
        '';
        type = types.int;
        default = 800000;
      };
      fidoAuth = mkEnableOption "FIDO authentication for the login user.";
      createRecoveryKey = mkEnableOption "Recovery key for the login user";
    };
  };

in
{
  options.ghaf.users = {
    # Main UI user
    homedUser = mkOption {
      description = "User account for desktop login.";
      type = homedUserAccount;
      default = { };
    };
  };

  config = mkIf cfg.homedUser.enable {

    assertions = [
      {
        assertion = cfg.homedUser.enable -> !cfg.proxyUser.enable;
        message = "You cannot enable both homed and proxy users at the same time.";
      }
      {
        assertion = cfg.homedUser.enable -> !cfg.appUser.enable;
        message = "You cannot enable both homed and app users at the same time.";
      }
      {
        assertion = cfg.homedUser.enable -> !cfg.adUsers.enable;
        message = "You cannot enable both homed and AD users at the same time.";
      }
    ];

    # Enable homed service
    services.homed.enable = true;

    ghaf = {
      # Enable systemd support
      systemd = {
        withHomed = true;
      }
      // optionalAttrs cfg.homedUser.fidoAuth {
        # Enable support for FIDO authentication
        withFido2 = true;
        withCryptsetup = true;
      };
    }
    // optionalAttrs (lib.hasAttr "storagevm" config.ghaf) {
      # Enable persistent storage for systemd-homed
      storagevm = {
        directories = [
          {
            directory = "/var/lib/systemd/home";
            user = "root";
            group = "root";
            mode = "0600";
          }
        ];
      };
    };

    systemd = {
      services = {
        systemd-homed.serviceConfig.Restart = "on-failure";

        # First boot login user setup service
        setup-ghaf-user =
          let
            userSetupScript = pkgs.writeShellApplication {
              name = "setup-ghaf-user";
              runtimeInputs = [
                pkgs.coreutils
                pkgs.ncurses
                pkgs.brightnessctl
                pkgs.fido2-manage
              ];
              text = ''
                set +e
                trap ''' INT

                # Consider 'systemctl stop' as normal exit
                trap 'exit 0' TERM

                brightnessctl set 100%

                SETUP_COMPLETE=false
                until $SETUP_COMPLETE; do
                  clear
                  FIDO_SUPPORT=""

                  echo -e "\e[1;32;1mWelcome to Ghaf \e[0m"
                  echo ""
                  echo "Start by creating your user account."
                  echo ""
              ''
              # FIDO2 device support is currently optional. Adjust this if mandatory support is required
              + optionalString cfg.homedUser.fidoAuth ''
                # Make sure FIDO2 device is connected before proceeding
                FIDO2_DEV=$(fido2-token2 -L)
                if [ -n "$FIDO2_DEV" ]; then
                  FIDO_SUPPORT="auto"
                fi
              ''
              + ''
                # Read new user name
                ACCEPTABLE_USER=false
                until $ACCEPTABLE_USER; do
                  read -e -r -p "Enter your user name: " USERNAME
                  USERNAME=''${USERNAME// /_}
                  USERNAME=''${USERNAME//[^a-zA-Z0-9_-]/}
                  USERNAME=''$(echo -n "$USERNAME" | tr '[:upper:]' '[:lower:]')
                  if [ -z "$USERNAME" ]; then
                    echo "User name cannot be empty. Please try again."
                  elif grep -q "^$USERNAME:" /etc/passwd; then
                    echo "User $USERNAME already exists. Please choose another user name."
                  else
                    ACCEPTABLE_USER=true
                  fi
                done

                echo ""
                ACCEPTABLE_REALNAME=false
                until $ACCEPTABLE_REALNAME; do
                  read -e -r -p "Enter your full name: " REALNAME
                  REALNAME=''${REALNAME//[^a-zA-Z ]/}
                  if [ -z "$REALNAME" ]; then
                    echo "Real name cannot be empty. Please try again."
                  else
                    ACCEPTABLE_REALNAME=true
                  fi
                done

                echo ""
                echo "Setting up your user account and creating encrypted home folder after you enter your password."
                echo "This may take a while..."
                echo ""

                # Add login user and home
                if ! homectl create "$USERNAME" \
                --real-name="$REALNAME" \
                --skel=/etc/skel \
                --storage=luks \
                --recovery-key=${lib.boolToString cfg.homedUser.createRecoveryKey} \
                --luks-pbkdf-type=argon2id \
                --fs-type=btrfs \
                --enforce-password-policy=true \
                --fido2-device="$FIDO_SUPPORT" \
                --drop-caches=true \
                --nosuid=true \
                --noexec=true \
                --nodev=true \
                --disk-size=${toString cfg.homedUser.homeSize}M \
                --shell=/run/current-system/sw/bin/bash \
                --uid=${toString cfg.homedUser.uid} \
                --member-of=users${
                  optionalString (
                    cfg.homedUser.extraGroups != [ ]
                  ) ",${concatStringsSep "," cfg.homedUser.extraGroups}"
                }; then
                  echo "An error occurred while creating the user account. Please try again." >&2
              ''
              + optionalString cfg.homedUser.fidoAuth ''
                echo "(HINT: You may have inserted a FIDO2/Yubikey after boot.)" >&2
                echo "(      - If you want to use a FIDO2 device, please restart the machine with the device inserted.)" >&2
                echo "(      - If you DONT want to use a FIDO2 device, please remove it and continue.)" >&2
              ''
              + ''
                  while true; do
                    read -r -p 'Press [Enter] to restart user setup...'
                    break
                  done
                  continue
                fi

                echo ""
                echo "User '$USERNAME' created successfully with the following details:"
                echo "  User Name:    $USERNAME"
                echo "  Display Name: $REALNAME"
              ''
              + optionalString cfg.homedUser.fidoAuth ''
                if [ -n "$FIDO_SUPPORT" ]; then
                  echo "  FIDO2 Device: Supported"
                else
                  echo "  FIDO2 Device: Not configured"
                fi
              ''
              + ''
                echo ""

                # Discard any previous inputs (e.g., from tapping the Yubikey)
                # shellcheck disable=SC2162
                while read -e -t 1; do : ; done

                # User to confirm the setup
                read -r -p 'Do you want to continue with this configuration? [Y/n] ' response
                case "$response" in
                [nN][oO] | [nN])
                  homectl remove "$USERNAME"
                  rm -r /var/lib/systemd/home/*
                  ;;
                *)
                  echo "Setup completed. Starting user session..."
                  SETUP_COMPLETE=true
                  ;;
                esac

                done # until $SETUP_COMPLETE

                 # Lock user creation script
                install -m 000 /dev/null /var/lib/nixos/user.lock
              '';
            };
          in
          {
            description = "First boot user setup";
            enable = true;
            requiredBy = [ "multi-user.target" ];
            before = [ "greetd.service" ];
            path = [ userSetupScript ];
            unitConfig.ConditionPathExists = "!/var/lib/nixos/user.lock";
            serviceConfig = {
              Type = "oneshot";
              StandardInput = "tty";
              StandardOutput = "tty";
              StandardError = "tty";
              TTYPath = "/dev/tty1";
              TTYReset = true;
              TTYVHangup = true;
              ExecStart = "${userSetupScript}/bin/setup-ghaf-user";
              Restart = "on-failure";
            };
          };

        setup-test-user =
          let
            automatedUserSetupScript = pkgs.writeShellApplication {
              name = "setup-test-user";
              runtimeInputs = [
                pkgs.coreutils
              ];
              text = ''
                echo "Automated boot user setup script"

                # Hardcoded user name
                USERNAME="testuser"
                REALNAME="Test User"
                export PASSWORD="testpw"
                export NEWPASSWORD="testpw"

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
                --disk-size=${toString cfg.homedUser.homeSize}M \
                --shell=/run/current-system/sw/bin/bash \
                --uid=${toString cfg.homedUser.uid} \
                --member-of=users${
                  optionalString (
                    cfg.homedUser.extraGroups != [ ]
                  ) ",${concatStringsSep "," cfg.homedUser.extraGroups}"
                }

                # Lock user creation script
                install -m 000 /dev/null /var/lib/nixos/user.lock
                echo "User $USERNAME created."

                # Stop interactive user setup service
                systemctl stop setup-ghaf-user
              '';
            };
          in
          mkIf config.ghaf.profiles.debug.enable {
            description = "Automated boot user setup script";
            enable = true;
            path = [ automatedUserSetupScript ];
            unitConfig.ConditionPathExists = "!/var/lib/nixos/user.lock";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${automatedUserSetupScript}/bin/setup-test-user";
            };
          };
      };
    };
  };
}
