# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.users.network.account;
in
  with lib; {
    options.ghaf.users.network.account = {
      enable = mkEnableOption "Network account Setup";
      user = mkOption {
        default = "network";
        type = with types; str;
        description = "Network user in system";
      };
      password = mkOption {
        default = "ghaf";
        type = with types; str;
        description = "Default password for Network user";
      };
    };

    config = mkIf cfg.enable {
      users = {
        users."${cfg.user}" = {
          isSystemUser = true;
          inherit (cfg) password;
          # networkmanager group is needed to run nm-launcher
          extraGroups = ["networkmanager"];
          group = cfg.user;
        };
        groups."${cfg.user}" = {
          name = cfg.user;
          members = [cfg.user];
        };
      };
    };
  }
