# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkDefault
    ;
  cfg = config.ghaf.users.profile;
  hasStorageVm = config.ghaf.storagevm.enable;
in
{
  _file = ./profiles.nix;

  options.ghaf.users.profile = {
    homed-user = {
      enable = mkEnableOption ''
        local systemd-homed managed user. This is the default for a single user system that does not require remote
        management.
      '';
    };
    ad-users = {
      enable = mkEnableOption ''
        Active Directory users for UI login. To use this option, you need Active Directory configured (backend) and
        locally the SSSD service. It further requires the computer to be enrolled in the Active Directory domain.

        Account restrictions such as single user login on the machine have to be configured via AD policies (e.g., GPO).
        Otherwise, all domain users will be able to login to the machine.

        Note: This profile is not compatible with 'homed-user' profile.
      '';
    };
    mutable-users = {
      enable = mkEnableOption ''
        mutable (configuration defined) user accounts, which allows to modify local user accounts at runtime.

        This applies only to configuration 'managed' user accounts, it does not affect homed or AD users. Passwords
        and hashes of configuration defined accounts will be stored in the /nixos/store and thus are immutable at runtime
        unless this option is enabled. This also applies to other user attributes like uid/gid, shell, home directory,
        groups, etc. Make sure to read the nixos documentation for users.mutableUsers for more information such as
        priority of the different password and hash options.

        This means:
          - enabled (true) - you can change the password of the configuration defined user at runtime,
            but you cannot change the users password by rebuilding the system
          - disabled (false), all user accounts are immutable and can only be changed via NixOS configuration rebuilds,
            and hashes (or passwords) will be stored in the /nixos/store
      '';
    };
  };

  config = {

    assertions = [
      {
        assertion = cfg.ad-users.enable -> !cfg.homed-user.enable;
        message = "You cannot enable both systemd-homed and active directory user profiles at the same time.";
      }
    ];

    # Disable mutable users
    users.mutableUsers = mkDefault cfg.mutable-users.enable;

    # Enable userborn
    services.userborn = {
      enable = mkDefault true;
      passwordFilesLocation = if hasStorageVm then "/var/lib/nixos" else "/etc";
    };

    # Userborn storage location
    ghaf.storagevm.directories = lib.mkIf hasStorageVm [
      "/var/lib/nixos"
    ];
  };
}
