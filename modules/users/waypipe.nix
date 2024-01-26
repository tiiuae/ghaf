# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.users.waypipe.account;
in
  with lib; {
    options.ghaf.users.waypipe.account = {
      enable = mkEnableOption "Waypipe account Setup";
      user = mkOption {
        default = "waypipe";
        type = with types; str;
        description = "Waypipe user in system";
      };
      password = mkOption {
        default = "ghaf";
        type = with types; str;
        description = "Default password for Waypipe user";
      };
    };

    config = mkIf cfg.enable {
      users = {
        users."${cfg.user}" = {
          isSystemUser = true;
          inherit (cfg) password;
          # To fix gui-vm weston: This account is currently not available
          shell = pkgs.bash;
          # To fix gui-vm weston: chrome_crashpad_handler: --database is required
          home = "/home/waypipe";
          createHome = true;
          group = cfg.user;
          #extraGroups = ["operator"];
        };
        groups."${cfg.user}" = {
          name = cfg.user;
          members = [cfg.user];
        };
      };
      #users.users.waypipe.group = "waypipe";
    };
  }
