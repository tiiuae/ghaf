# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.services.github;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;
in
{
  options.ghaf.services.github = {
    enable = mkEnableOption "Github configurations";
    owner = mkOption {
      type = types.str;
      description = ''
        Github owner account of the bug reporter issue
      '';
    };
    repo = mkOption {
      type = types.str;
      description = ''
        Github repo of the bug reporter issue
      '';
    };
    token = mkOption {
      type = types.str;
      description = ''
        Personal token of the bug reporter Github account
      '';
    };
  };

  config = mkIf cfg.enable {

    systemd.user.services."github-config" =
      let
        configScript = pkgs.writeShellScriptBin "github-config" ''
          mkdir -p "$HOME"/.config/ctrl-panel
          cat > "$HOME"/.config/ctrl-panel/config.toml << EOF
          token = "${cfg.token}"
          owner = "${cfg.owner}"
          repo = "${cfg.repo}"
          EOF
        '';
      in
      {
        enable = true;
        description = "Generate Github configuration file for Ghaf Control Panel";
        path = [ configScript ];
        wantedBy = [ "ewwbar.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          StandardOutput = "journal";
          StandardError = "journal";
          ExecStart = "${configScript}/bin/github-config";
        };
      };
  };
}
