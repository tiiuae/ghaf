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

  imports = [
    (lib.mkRemovedOptionModule [ "ghaf" "services" "github" "token" ] ''
      Use ghaf.services.github.tokenFile instead: an absolute path to a file
      read at runtime. Do not inline the token value -- the removed option
      copied it into the world-readable Nix store of every image.
    '')
  ];

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
          runtimeInputs = [ pkgs.coreutils ];
          text = ''
            # The file holds a GitHub token: keep it owner-only. Without this
            # the inherited 022 umask would make it world-readable, which is
            # the leak tokenFile exists to close.
            umask 077
            conf_dir="$HOME/.config/ctrl-panel"
            mkdir -p "$conf_dir"

            token=""
            ${lib.optionalString (cfg.tokenFile != null) ''
              # Read into a variable first. As an argument to printf a failing
              # $(cat ...) would not fail the unit, and an unreadable file
              # would be silently indistinguishable from an empty token.
              if ! token=$(cat ${lib.escapeShellArg cfg.tokenFile}); then
                echo "github-config: cannot read ${cfg.tokenFile}" >&2
                exit 1
              fi
              if [ -z "$token" ]; then
                echo "github-config: ${cfg.tokenFile} is empty" >&2
                exit 1
              fi
            ''}

            # Write via a temp file: a plain redirect truncates the existing
            # config before the content is known to be good.
            tmp=$(mktemp "$conf_dir/.config.toml.XXXXXX")
            trap 'rm -f "$tmp"' EXIT
            {
              printf 'token = "%s"\n' "$token"
              printf 'owner = "%s"\n' ${lib.escapeShellArg cfg.owner}
              printf 'repo = "%s"\n' ${lib.escapeShellArg cfg.repo}
            } > "$tmp"
            mv "$tmp" "$conf_dir/config.toml"
          '';
        };
      in
      {
        enable = true;
        description = "Generate Github configuration file for Ghaf Control Panel";
        wantedBy = [ "default.target" ];
        # ewwbar/ctrl-panel reads config.toml at startup; wantedBy alone does
        # not order the two.
        before = [ "ewwbar.service" ];
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
