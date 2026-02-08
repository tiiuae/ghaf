# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
  _file = ./github.nix;

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
    clientId = mkOption {
      type = types.str;
      default = "178c6fc778ccc68e1d6a";
      description = ''
        GitHub OAuth client ID for bug reporting.
        Default is the public GitHub CLI OAuth app client ID.
      '';
    };
  };

  config = mkIf cfg.enable {

    environment.sessionVariables = {
      GITHUB_CONFIG = "$HOME/.config/ctrl-panel/config.toml";
      # TODO: Current client ID belongs to the "GitHub CLI" OAuth app. Replace it with TII Github app
      # GITHUB App Client ID for bug reporting login
      # NOTE: This is a public OAuth client ID for GitHub CLI, not a secret
      # Moving to configurable option to avoid hardcoding in source
      GITHUB_CLIENT_ID = cfg.clientId;
    };

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
