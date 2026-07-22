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
    tokenFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Absolute path to a file containing the personal token of the bug
        reporter Github account, read at runtime. Do not use a Nix path
        literal here - that would copy the secret into the world-readable
        Nix store. When null, an empty token is written and ctrl-panel
        updates it after user login.
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
        configScript = pkgs.writeShellApplication {
          name = "github-config";
          text = ''
            mkdir -p "$HOME/.config/ctrl-panel"
            {
              ${
                if cfg.tokenFile != null then
                  ''printf 'token = "%s"\n' "$(cat ${lib.escapeShellArg cfg.tokenFile})"''
                else
                  # Populated by ctrl-panel after the user logs in
                  ''printf 'token = ""\n' ''
              }
              printf 'owner = "%s"\n' ${lib.escapeShellArg cfg.owner}
              printf 'repo = "%s"\n' ${lib.escapeShellArg cfg.repo}
            } > "$HOME/.config/ctrl-panel/config.toml"
          '';
        };
      in
      {
        enable = true;
        description = "Generate Github configuration file for Ghaf Control Panel";
        wantedBy = [ "default.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          StandardOutput = "journal";
          StandardError = "journal";
          ExecStart = lib.getExe configScript;
        };
      };
  };
}
