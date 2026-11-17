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
    enable = lib.mkEnableOption "Chromium program settings";
    openInNormalExtension = lib.mkEnableOption "browser extension to open links in the normal browser";
    webRtcUdpPorts = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            from = lib.mkOption {
              type = lib.types.port;
              description = "First port of the range.";
            };
            to = lib.mkOption {
              type = lib.types.port;
              description = "Last port of the range.";
            };
          };
        }
      );
      # Above the kernel's ephemeral range, so no other socket takes them.
      default = {
        from = 61000;
        to = 61099;
      };
      description = "Local UDP port range WebRTC is held to, and may send from to any destination; null leaves WebRTC unconstrained.";
    };
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
      }
      // lib.optionalAttrs (cfg.webRtcUdpPorts != null) {
        WebRtcUdpPortRange = "${toString cfg.webRtcUdpPorts.from}-${toString cfg.webRtcUdpPorts.to}";
      };
    };

    ghaf.firewall.allowedUDPPorts = lib.mkIf (cfg.webRtcUdpPorts != null) [
      {
        port = cfg.webRtcUdpPorts;
        direction = "output";
        filter = "src";
      }
    ];

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
