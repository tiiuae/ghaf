# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.reference.programs.google-chrome;
in
{
  options.ghaf.reference.programs.google-chrome = {
    enable = lib.mkEnableOption "Enable Google chrome program settings";
    useZathuraVM = lib.mkEnableOption "Open PDFs in Zathura VM";
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
        StartupBrowserWindowLaunchSuppressed = true;
        DeviceMetricsReportingEnabled = false;
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
      default = {

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
  };
  config = lib.mkIf cfg.enable {

    environment.etc = {
      "opt/chrome/policies/managed/default.json" = lib.mkIf (cfg.defaultPolicy != { }) {
        text = builtins.toJSON cfg.defaultPolicy;
      };
      "opt/chrome/policies/managed/extra.json" = lib.mkIf (cfg.extraOpts != { }) {
        text = builtins.toJSON cfg.extraOpts;
      };

    };
  };
}
