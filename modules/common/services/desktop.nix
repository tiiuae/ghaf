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
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start chromium";
              icon = "${pkgs.icon-pack}/chromium.svg";
            }

            {
              name = "Trusted Browser";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm business-vm chromium";
              icon = "${pkgs.icon-pack}/thorium-browser.svg";
            }
            # TODO must enable the waypipe to support more than one app in a VM
            {
              name = "VPN";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm business-vm gpclient";
              icon = "${pkgs.icon-pack}/yast-vpn.svg";
            }

            {
              name = "Microsoft Outlook";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm business-vm outlook";
              icon = "${pkgs.icon-pack}/ms-outlook.svg";
            }
            {
              name = "Microsoft 365";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm business-vm office";
              icon = "${pkgs.icon-pack}/microsoft-365.svg";
            }
            {
              name = "Teams";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm business-vm teams";
              icon = "${pkgs.icon-pack}/teams-for-linux.svg";
            }

            {
              name = "GALA";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start gala";
              icon = "${pkgs.icon-pack}/distributor-logo-android.svg";
            }

            {
              name = "PDF Viewer";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start zathura";
              icon = "${pkgs.icon-pack}/document-viewer.svg";
            }

            {
              name = "Element";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm comms-vm element";
              icon = "${pkgs.icon-pack}/element-desktop.svg";
            }

            {
              name = "Slack";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start --vm comms-vm slack";
              icon = "${pkgs.icon-pack}/slack.svg";
            }

            {
              name = "AppFlowy";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} start appflowy";
              icon = "${pkgs.appflowy}/opt/data/flutter_assets/assets/images/flowy_logo.svg";
            }

            {
              name = "Network Settings";
              path = "${pkgs.nm-launcher}/bin/nm-launcher";
              icon = "${pkgs.icon-pack}/preferences-system-network.svg";
            }

            {
              name = "Bluetooth Settings";
              path = "${pkgs.bt-launcher}/bin/bt-launcher";
              icon = "${pkgs.icon-pack}/bluetooth-48.svg";
            }

            {
              name = "Shutdown";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} poweroff";
              icon = "${pkgs.icon-pack}/system-shutdown.svg";
            }

            {
              name = "Reboot";
              path = "${pkgs.givc-cli}/bin/givc-cli ${cliArgs} reboot";
              icon = "${pkgs.icon-pack}/system-reboot.svg";
            }
          ]
          ++ optionals config.ghaf.reference.programs.windows-launcher.enable [
            {
              name = "Windows";
              path = "${pkgs.virt-viewer}/bin/remote-viewer -f spice://${winConfig.spice-host}:${toString winConfig.spice-port}";
              icon = "${pkgs.icon-pack}/distributor-logo-windows.svg";
            }
          ];
      };
    };
  };
}
