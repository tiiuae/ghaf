# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.reference.programs.google-chrome;
in
{
  options.ghaf.reference.programs.google-chrome = {
    enable = lib.mkEnableOption "Enable Google chrome program settings";
    openInNormalExtension = lib.mkEnableOption "browser extension to open links in the normal browser";
    defaultPolicy = lib.mkOption {
      type = lib.types.attrs;
      description = ''
        Google chrome policy options. A list of available policies
        can be found in the Chrome Enterprise documentation:
        <https://cloud.google.com/docs/chrome-enterprise/policies/>
        Make sure the selected policy is supported on Linux and your browser version.
      '';
      default = {
        PromptForDownloadLocation = true;
        AlwaysOpenPdfExternally = true;
        DefaultBrowserSettingEnabled = true;
        MetricsReportingEnabled = false;
      };
      example = lib.literalExpression ''
        {
          PromptForDownloadLocation=true;
        }
      '';
    };

    extraOpts = lib.mkOption {
      type = lib.types.attrs;
      description = ''
        Extra google chrome policy options. A list of available policies
        can be found in the Chrome Enterprise documentation:
        <https://cloud.google.com/docs/chrome-enterprise/policies/>
        Make sure the selected policy is supported on Linux and your browser version.
      '';
      default =
        {
        };
      example = lib.literalExpression ''
        {
          "BrowserSignin" = 0;
          "SyncDisabled" = true;
          "PasswordManagerEnabled" = false;
          "SpellcheckEnabled" = true;
          "SpellcheckLanguage" = [
            "de"
            "en-US"
          ];
        }
      '';
    };

    policyOwner = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "Policy files owner";
    };

    policyOwnerGroup = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "Policy files group";
    };
  };
  config = lib.mkIf cfg.enable {

    environment.etc = lib.mkMerge [
      {
        "opt/chrome/policies/managed/default.json" = {
          text = builtins.toJSON cfg.defaultPolicy;
          user = "${cfg.policyOwner}"; # Owner is proxy-user
          group = "${cfg.policyOwnerGroup}"; # Group is proxy-admin
          mode = "0664"; # Permissions: read/write for owner/group, no permissions for others
        };
        "opt/chrome/policies/managed/extra.json" = {
          text = builtins.toJSON cfg.extraOpts;
          user = "${cfg.policyOwner}"; # Owner is proxy-user
          group = "${cfg.policyOwnerGroup}"; # Group is proxy-admin
          mode = "0664"; # Permissions: read/write for owner/group, no permissions for others
        };
      }
      (lib.mkIf (cfg.openInNormalExtension && config.ghaf.givc.enable) {
        "opt/chrome/native-messaging-hosts/fi.ssrc.open_normal.json" = {
          source = "${pkgs.open-normal-extension}/fi.ssrc.open_normal.json";
        };

        "open-normal-extension.cfg" = {
          text =
            let
              cliArgs = builtins.replaceStrings [ "\n" ] [ " " ] ''
                --name ${config.ghaf.givc.adminConfig.name}
                --addr ${config.ghaf.givc.adminConfig.addr}
                --port ${config.ghaf.givc.adminConfig.port}
                ${lib.optionalString config.ghaf.givc.enableTls "--cacert /run/givc/ca-cert.pem"}
                ${lib.optionalString config.ghaf.givc.enableTls "--cert /run/givc/business-vm-cert.pem"}
                ${lib.optionalString config.ghaf.givc.enableTls "--key /run/givc/business-vm-key.pem"}
                ${lib.optionalString (!config.ghaf.givc.enableTls) "--notls"}
              '';
            in
            ''
              export GIVC_PATH="${pkgs.givc-cli}"
              export GIVC_OPTS="${cliArgs}"
            '';
        };
      })
    ];
  };
}
