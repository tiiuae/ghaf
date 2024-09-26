# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.services.disks;
  yaml = pkgs.formats.yaml { };
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;
in
{
  options.ghaf.services.disks = {
    enable = mkEnableOption "Enable disk mount daemon";

    fileManager = mkOption {
      type = types.str;
      default = "xdg-open";
      description = "The program to open mounted directories";
    };
  };
  config = mkIf cfg.enable {

    services.udisks2.enable = true;

    environment.etc."udiskie.yml".source = yaml.generate "udiskie.yml" {
      program_options = {
        automount = true;
        tray = "auto";
        notify = true;
      };
    };

    systemd.user.services.udiskie = {
      enable = true;
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.udiskie}/bin/udiskie -c /etc/udiskie.yml -f ${cfg.fileManager} --appindicator";
      };
      after = [ "ghaf-session.target" ];
      partOf = [ "ghaf-session.target" ];
      wantedBy = [ "ghaf-session.target" ];
    };
  };
}
