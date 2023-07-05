# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.services.dendrite;
  private_key = "/etc/dendrite/keys/private_key.pem";
in
  with lib; {
    options.ghaf.services.dendrite = {
      enable = mkEnableOption "Service dendrite";
      # TODO add options to configure dendrite server
    };

    config = mkIf cfg.enable {
      services.dendrite = {
        enable = true;
        settings.global = {
          server_name = config.networking.hostName;
          private_key = private_key;
        };
      };
      #https://github.com/NixOS/nixpkgs/issues/225845
      systemd.services.dendrite.serviceConfig.DynamicUser = lib.mkForce false;
      systemd.services.dendrite.serviceConfig.ExecStartPre = lib.mkForce [
        ''${pkgs.bash}/bin/bash -c "if [ ! -f ${private_key} ]; then ${pkgs.coreutils}/bin/mkdir -p /etc/dendrite/keys; ${pkgs.dendrite}/bin/generate-keys --private-key ${private_key}; ${pkgs.coreutils}/bin/chmod 666 ${private_key}; fi;"''
      ];
    };
  }
