# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.users.ghaf.account;
in
  with lib; {
    options.ghaf.users.ghaf.account = {
      enable = mkEnableOption "Ghaf account Setup";
      user = mkOption {
        default = "ghaf";
        type = with types; str;
        description = "Ghaf user in system";
      };
      password = mkOption {
        default = "ghaf";
        type = with types; str;
        description = "Default password for Ghaf user";
      };
    };

    config = mkIf cfg.enable {
      users = {
        users."${cfg.user}" = {
          isNormalUser = true;
          inherit (cfg) password;
          # Add root user only for debug builds
          extraGroups = lib.mkIf config.ghaf.profiles.debug.enable ["wheel"];
        };
        groups."${cfg.user}" = {
          name = cfg.user;
          members = [cfg.user];
        };
      };
    };
  }
