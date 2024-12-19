# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (builtins) hasAttr replaceStrings;
  inherit (lib)
    mkIf
    mkEnableOption
    optionals
    optionalAttrs
    optionalString
    ;

  cfg = config.ghaf.services.desktop;

  winConfig =
    if (hasAttr "reference" config.ghaf) then
      if (hasAttr "programs" config.ghaf.reference) then
        config.ghaf.reference.programs.windows-launcher
      else
        { }
    else
      { };
in
# TODO: The desktop configuration needs to be re-worked.
# TODO it needs to be moved out of common and the launchers have to be set bu the reference programs NOT here
{
  options.ghaf.services.desktop = {
    enable = mkEnableOption "Enable the desktop configuration";
  };

  config = mkIf (cfg.enable && config.ghaf.givc.enable) {
    ghaf = optionalAttrs (hasAttr "graphics" config.ghaf) {
      profiles.graphics.compositor = "labwc";
      graphics = {
        launchers =
          let
            cliArgs = replaceStrings [ "\n" ] [ " " ] ''
              --name ${config.ghaf.givc.adminConfig.name}
              --addr ${config.ghaf.givc.adminConfig.addr}
              --port ${config.ghaf.givc.adminConfig.port}
              ${optionalString config.ghaf.givc.enableTls "--cacert /run/givc/ca-cert.pem"}
              ${optionalString config.ghaf.givc.enableTls "--cert /run/givc/gui-vm-cert.pem"}
              ${optionalString config.ghaf.givc.enableTls "--key /run/givc/gui-vm-key.pem"}
              ${optionalString (!config.ghaf.givc.enableTls) "--notls"}
            '';
          in
          [
            # {
            #   # The SPKI fingerprint is calculated like this:
            #   # $ openssl x509 -noout -in mitmproxy-ca-cert.pem -pubkey | openssl asn1parse -noout -inform pem -out public.key
            #   # $ openssl dgst -sha256 -binary public.key | openssl enc -base64
            #   name = "Chromium";
            #   description = "Isolated General Browsing";
            #   vm = "Chromium";
            #   path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start chromium";
            #   icon = "chromium";
            # }

            {
              name = "Trusted Browser";
              description = "Isolated Trusted Browsing";
              vm = "Business";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm business-vm google-chrome";
              icon = "thorium-browser";
            }
            {
              # The SPKI fingerprint is calculated like this:
              # $ openssl x509 -noout -in mitmproxy-ca-cert.pem -pubkey | openssl asn1parse -noout -inform pem -out public.key
              # $ openssl dgst -sha256 -binary public.key | openssl enc -base64
              name = "Google Chrome";
              description = "Isolated General Browsing";
              vm = "Chrome";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm chrome-vm google-chrome";
              icon = "google-chrome";
            }

            {
              name = "VPN";
              description = "GlobalProtect VPN Client";
              vm = "Business";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm business-vm gpclient";
              icon = "yast-vpn";
            }

            {
              name = "Microsoft Outlook";
              description = "Microsoft Email Client";
              vm = "Business";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm business-vm outlook";
              icon = "ms-outlook";
            }
            {
              name = "Microsoft 365";
              description = "Microsoft 365 Software Suite";
              vm = "Business";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm business-vm office";
              icon = "microsoft-365";
            }
            {
              name = "Teams";
              description = "Microsoft Teams Collaboration Application";
              vm = "Business";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm business-vm teams";
              icon = "teams-for-linux";
            }
            {
              name = "Text Editor";
              description = "Simple Text Editor";
              vm = "Business";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm business-vm gnome-text-editor";
              icon = "org.gnome.TextEditor";
            }
            {
              name = "Xarchiver";
              description = "File Compressor";
              vm = "Business";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm business-vm xarchiver";
              icon = "xarchiver";
            }

            {
              name = "GALA";
              description = "Secure Android-in-the-Cloud";
              vm = "GALA";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start gala";
              icon = "distributor-logo-android";
            }

            {
              name = "PDF Viewer";
              description = "Isolated PDF Viewer";
              vm = "Zathura";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm zathura-vm zathura";
              icon = "document-viewer";
            }

            {
              name = "Element";
              description = "General Messaging Application";
              vm = "Comms";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm comms-vm element";
              icon = "element-desktop";
            }

            {
              name = "Slack";
              description = "Teams Collaboration & Messaging Application";
              vm = "Comms";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm comms-vm slack";
              icon = "slack";
            }

            {
              name = "Zoom";
              description = "Zoom Videoconferencing Application";
              vm = "Comms";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm comms-vm zoom";
            }

            {
              name = "Calculator";
              description = "Solve Math Problems";
              path = "${pkgs.gnome-calculator}/bin/gnome-calculator";
              icon = "${pkgs.gnome-calculator}/share/icons/hicolor/scalable/apps/org.gnome.Calculator.svg";
            }

            {
              name = "Sticky Notes";
              description = "Sticky Notes on your Desktop";
              path = "${pkgs.sticky-notes}/bin/com.vixalien.sticky";
              icon = "${pkgs.sticky-notes}/share/icons/hicolor/scalable/apps/com.vixalien.sticky.svg";
            }

            {
              name = "File Manager";
              description = "Organize & Manage Files";
              path = "${pkgs.pcmanfm}/bin/pcmanfm";
              icon = "system-file-manager";
            }

            {
              name = "Bluetooth Settings";
              description = "Manage Bluetooth Devices & Settings";
              path = "${pkgs.bt-launcher}/bin/bt-launcher";
              icon = "bluetooth-48";
            }

            {
              name = "Audio Control";
              description = "System Audio Control";
              path = "${pkgs.dbus}/bin/dbus-send --session --print-reply --dest=org.ghaf.Audio /org/ghaf/Audio org.ghaf.Audio.Open";
              icon = "preferences-sound";
            }

            {
              name = "Video Editor";
              description = "Losslesscut Video Editor";
              vm = "Business";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm business-vm losslesscut";
              icon = "${pkgs.losslesscut-bin}/share/icons/losslesscut.png";
            }

            {
              name = "Falcon AI";
              description = "Your local large language model, developed by TII.";
              path = "${pkgs.alpaca}/bin/alpaca";
              icon = "${pkgs.ghaf-artwork}/icons/falcon-icon.svg";
            }

            {
              name = "Control panel";
              path = "${pkgs.ctrl-panel}/bin/ctrl-panel";
              icon = "utilities-tweak-tool";
            }
          ]
          ++ optionals config.ghaf.reference.programs.windows-launcher.enable [
            {
              name = "Windows";
              description = "Virtualized Windows System";
              path = "${pkgs.virt-viewer}/bin/remote-viewer -f spice://${winConfig.spice-host}:${toString winConfig.spice-port}";
              icon = "distributor-logo-windows";
            }
          ];
      };
    };
  };
}
