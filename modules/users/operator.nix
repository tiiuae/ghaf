# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.users.operator.account;
  yubikeyCfg = config.ghaf.passwordless.authentication.enable;
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
        users."${cfg.user}" = mkMerge [
          {
            isNormalUser = true;
            inherit (cfg) password;
            # Video group is needed to run GUI
            extraGroups = ["video"];
          }
          (
            if yubikeyCfg
            then {
              password = mkForce null;
            }
            else {
              inherit (cfg) password;
            }
          )
        ];
        groups."${cfg.user}" = {
          name = cfg.user;
          members = [cfg.user];
        };
      };
    };
  }
