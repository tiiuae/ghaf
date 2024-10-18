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
            {
              # The SPKI fingerprint is calculated like this:
              # $ openssl x509 -noout -in mitmproxy-ca-cert.pem -pubkey | openssl asn1parse -noout -inform pem -out public.key
              # $ openssl dgst -sha256 -binary public.key | openssl enc -base64
              name = "Chromium";
              description = "Isolated General Browsing";
              vm = "Chromium";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start chromium";
              icon = "${pkgs.icon-pack}/chromium.svg";
            }

            {
              name = "Trusted Browser";
              description = "Isolated Trusted Browsing";
              vm = "Business";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm business-vm chromium";
              icon = "${pkgs.icon-pack}/thorium-browser.svg";
            }

            {
              name = "VPN";
              description = "GlobalProtect VPN Client";
              vm = "Business";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm business-vm gpclient";
              icon = "${pkgs.icon-pack}/yast-vpn.svg";
            }

            {
              name = "Microsoft Outlook";
              description = "Microsoft Email Client";
              vm = "Business";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm business-vm outlook";
              icon = "${pkgs.icon-pack}/ms-outlook.svg";
            }
            {
              name = "Microsoft 365";
              description = "Microsoft 365 Software Suite";
              vm = "Business";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm business-vm office";
              icon = "${pkgs.icon-pack}/microsoft-365.svg";
            }
            {
              name = "Teams";
              description = "Microsoft Teams Collaboration Application";
              vm = "Business";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm business-vm teams";
              icon = "${pkgs.icon-pack}/teams-for-linux.svg";
            }
            {
              name = "Text Editor";
              description = "Simple Text Editor";
              vm = "Business";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm business-vm gnome-text-editor";
              icon = "${pkgs.icon-pack}/org.gnome.TextEditor.svg";
            }
            {
              name = "Xarchiver";
              description = "File Compressor";
              vm = "Business";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm business-vm xarchiver";
              icon = "${pkgs.icon-pack}/xarchiver.svg";
            }

            {
              name = "GALA";
              description = "Secure Android-in-the-Cloud";
              vm = "GALA";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start gala";
              icon = "${pkgs.icon-pack}/distributor-logo-android.svg";
            }

            {
              name = "PDF Viewer";
              description = "Isolated PDF Viewer";
              vm = "Zathura";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start zathura";
              icon = "${pkgs.icon-pack}/document-viewer.svg";
            }

            {
              name = "Element";
              description = "General Messaging Application";
              vm = "Comms";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm comms-vm element";
              icon = "${pkgs.icon-pack}/element-desktop.svg";
            }

            {
              name = "Slack";
              description = "Teams Collaboration & Messaging Application";
              vm = "Comms";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm comms-vm slack";
              icon = "${pkgs.icon-pack}/slack.svg";
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
              icon = "${pkgs.icon-pack}/system-file-manager.svg";
            }

            {
              name = "Bluetooth Settings";
              description = "Manage Bluetooth Devices & Settings";
              path = "${pkgs.bt-launcher}/bin/bt-launcher";
              icon = "${pkgs.icon-pack}/bluetooth-48.svg";
            }

            {
              name = "Audio Control";
              description = "System Audio Control";
              path = "${pkgs.ghaf-audio-control}/bin/GhafAudioControlStandalone --pulseaudio_server=audio-vm:4713";
              icon = "${pkgs.icon-pack}/preferences-sound.svg";
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
              icon = "${pkgs.icon-pack}/utilities-tweak-tool.svg";
            }
          ]
          ++ optionals config.ghaf.reference.programs.windows-launcher.enable [
            {
              name = "Windows";
              description = "Virtualized Windows System";
              path = "${pkgs.virt-viewer}/bin/remote-viewer -f spice://${winConfig.spice-host}:${toString winConfig.spice-port}";
              icon = "${pkgs.icon-pack}/distributor-logo-windows.svg";
            }
          ];
      };
    };
  };
}
