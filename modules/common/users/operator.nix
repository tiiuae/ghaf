# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.users.operator.account;
in
  with lib; {
    options.ghaf.users.operator.account = {
      enable = mkEnableOption "Operator account Setup";
      user = mkOption {
        default = "operator";
        type = with types; str;
        description = "Operator user in system";
      };
      password = mkOption {
        default = "ghaf";
        type = with types; str;
        description = "Default password for Operator user";
      };
    };

    config = mkIf cfg.enable {
      users = {
        users."${cfg.user}" = {
          isNormalUser = true;
          inherit (cfg) password;
          # Video group is needed to run GUI
          extraGroups = ["video"];
        };
        groups."${cfg.user}" = {
          name = cfg.user;
          members = [cfg.user];
        };
      };
    };
  }
