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
    mkMerge
    mkEnableOption
    mkOption
    optionals
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
      type = with types; str;
      description = ''
        A default user to create in the system.
      '';
    };
    password = mkOption {
      default = "ghaf";
      type = with types; str;
      description = ''
        A default password for the user.
      '';
    };
    readOnlyHome = mkEnableOption "read-only home directory" // {
      default = true;
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      users = {
        mutableUsers = false;
        users."${cfg.user}" = {
          isNormalUser = true;
          inherit (cfg) password;
          #TODO add "docker" use "lib.optionals"
          extraGroups = [
            "wheel"
            "video"
            "networkmanager"
          ] ++ optionals config.security.tpm2.enable [ "tss" ];
          # # Remove writing permission on home directory as it usually tmpfs.
          # homeMode = "500";
        };
        groups."${cfg.user}" = {
          name = cfg.user;
          members = [ cfg.user ];
        };
      };

      # to build ghaf as ghaf-user with caches
      nix.settings.trusted-users = mkIf config.ghaf.profiles.debug.enable [ cfg.user ];
      #services.userborn.enable = true;
    })
    (mkIf cfg.readOnlyHome {
      systemd.services.${"read-only-home-" + cfg.user} = {
        description = "Make home read only after everything is mounted";
        after = [ "local-fs.target" ];
        wantedBy = [ "multi-user.target" ];
        unitConfig = {
          RequiresMountsFor = config.users.users.${cfg.user}.home;
        };
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.coreutils}/bin/chmod 500 ${config.users.users.${cfg.user}.home}";
        };
      };
    })
  ];
}
