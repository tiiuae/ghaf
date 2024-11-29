# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.reference.programs.chromium;
in
{
  options.ghaf.reference.programs.chromium = {
    enable = lib.mkEnableOption "Enable Chromium program settings";
    openInNormalExtension = lib.mkEnableOption "browser extension to open links in the normal browser";
  };
  config = lib.mkIf cfg.enable {
    programs.chromium = {
      enable = true;

      initialPrefs = {
        # Fix border glitch when going maximised->minimised.
        browser.custom_chrome_frame = false;
        download.prompt_for_download = true;
      };

      # Don't use pdf.js, open externally.
      extraOpts."AlwaysOpenPdfExternally" = true;

    };

    environment.etc = lib.mkIf (cfg.openInNormalExtension && config.ghaf.givc.enable) {
      "chromium/native-messaging-hosts/fi.ssrc.open_normal.json" = {
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
    };
  };
}
