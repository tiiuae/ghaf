# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  options,
  ...
}:
# account for the development time login with sudo rights
let
  cfg = config.ghaf.users.accounts;
in
  with lib; {
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
    };

    config = mkIf cfg.enable {
      users = {
        mutableUsers = true;
        users."${cfg.user}" = {
          isNormalUser = true;
          password = cfg.password;
          #TODO add "docker" use "lib.optionals"
          extraGroups = ["wheel" "video" "networkmanager"];
        };
        groups."${cfg.user}" = {
          name = cfg.user;
          members = [cfg.user];
        };
      };
    };
  }
