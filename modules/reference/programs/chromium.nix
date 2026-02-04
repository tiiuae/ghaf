# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
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
  _file = ./chromium.nix;

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

      extraOpts = {
        # Don't use pdf.js, open externally.
        "AlwaysOpenPdfExternally" = true;
        "ExtensionInstallForcelist" =
          if cfg.openInNormalExtension then
            [ "${pkgs.chrome-extensions.open-normal.id};http://localhost:8080/update.xml" ]
          else
            [ ];
      };
    };

    environment.etc = lib.mkIf (cfg.openInNormalExtension && config.ghaf.givc.enable) {
      "chromium/native-messaging-hosts/fi.ssrc.open_normal.json" = {
        source = "${pkgs.chrome-extensions.open-normal}/fi.ssrc.open_normal.json";
      };

      "open-normal-extension.cfg" = {
        text = ''
          export GIVC_PATH="${pkgs.givc-cli}"
          export GIVC_OPTS="${config.ghaf.givc.cliArgs}"
        '';
      };
    };
  };
}
