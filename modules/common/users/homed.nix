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
    mkOption
    mkEnableOption
    optionalAttrs
    types
    ;

  homedUserAccount = types.submodule {
    options = {
      enable = mkEnableOption "a single homed user account";
      uid = mkOption {
        description = "Login user identifier (uid). Defaults to 1000 for compatibility.";
        type = types.int;
        default = 1000;
      };
      loginShell = mkOption {
        description = "Login shell for the user.";
        type = types.str;
        default = "/run/current-system/sw/bin/bash";
      };
      fsType = mkOption {
        description = "Filesystem type for the home directory.";
        type = types.str;
        default = "ext4";
      };
      extraGroups = mkOption {
        description = "Extra groups for the login user.";
        type = types.listOf types.str;
        default = [ ];
      };
      homeSize = mkOption {
        description = ''
          Size of the home directory for the login user in MiB (integer).
          The integer size is inherited from the microvm volume size parameter.
          Defaults to 400 GiB.
        '';
        type = types.int;
        default = 400 * 1024;
      };
      fidoAuth = mkEnableOption "FIDO authentication for the login user.";
    };
  };
in
{
  _file = ./homed.nix;

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
    // optionalAttrs config.ghaf.storagevm.enable {
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
        # Disable systemds' default firstboot user setup
        systemd-firstboot.enable = false;

        # Ensure homed service restarts on failure
        systemd-homed.serviceConfig.Restart = "on-failure";
      };
    };
  };
}
