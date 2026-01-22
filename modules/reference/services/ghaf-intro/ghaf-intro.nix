# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Ghaf Introduction Website Service
# Serves a local website explaining Ghaf's architecture and security model
#
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.reference.services.ghaf-intro;
in
{
  options.ghaf.reference.services.ghaf-intro = {
    enable = lib.mkEnableOption "Ghaf introduction website";

    address = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address for the local Ghaf intro web server to bind to";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port for the local Ghaf intro web server";
    };

    url = lib.mkOption {
      type = lib.types.str;
      default = "http://${cfg.address}:${toString cfg.port}";
      readOnly = true;
      description = "URL to access the Ghaf intro website";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.ghaf-intro-server = {
      description = "Local web server for Ghaf introduction website";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        ExecStart = "${pkgs.busybox}/bin/busybox httpd -f -p ${cfg.address}:${toString cfg.port} -h ${pkgs.ghaf-intro}";
        Type = "simple";
        Restart = "always";
        RestartSec = "5s";
        DynamicUser = true;
      };
    };
  };
}
