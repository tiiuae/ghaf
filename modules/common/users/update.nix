# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.users.update.account;
in
  with lib; {
    options.ghaf.users.update.account = {
      enable = mkEnableOption "Update account Setup";
      user = mkOption {
        default = "update";
        type = with types; str;
        description = "Update user in system";
      };
    };

    config = mkIf cfg.enable {
      users = {
        users."${cfg.user}" = {
          isSystemUser = true;
          hashedPassword = "!";
          shell = pkgs.bash;
          group = cfg.user;
        };
        groups."${cfg.user}" = {
          name = cfg.user;
          members = [cfg.user];
        };
      };
      nix.settings.trusted-users = [cfg.user];
      ## Need to add extraRules to avoid asking password during nixos-rebuild switch
      security.sudo.extraRules = [
        {
          users = [cfg.user];
          commands = [
            {
              command = "/run/current-system/sw/bin/switch-to-configuration";
              options = ["NOPASSWD"];
            }
            {
              command = "/run/current-system/sw/bin/nix-env";
              options = ["NOPASSWD"];
            }
            {
              command = "/run/current-system/sw/bin/systemd-run";
              options = ["NOPASSWD"];
            }
          ];
        }
      ];
    };
  }
