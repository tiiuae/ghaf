# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (builtins) filter map hasAttr;
  inherit (lib)
    mkIf
    mkEnableOption
    head
    any
    optionals
    optionalAttrs
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
  isIdsvmEnabled = any (vm: vm == "ids-vm") config.ghaf.namespaces.vms;
in
# TODO: The desktop configuration needs to be re-worked.
# TODO it needs to be moved out of common and the launchers have to be set bu the reference programs NOT here
{
  options.ghaf.services.desktop = {
    enable = mkEnableOption "Enable the desktop configuration";
  };

  config = mkIf cfg.enable {
    ghaf = optionalAttrs (hasAttr "graphics" config.ghaf) {
      profiles.graphics.compositor = "labwc";
      graphics = {
        launchers =
          let
            hostEntry = filter (
              x: x.name == "ghaf-host" + lib.optionalString config.ghaf.profiles.debug.enable "-debug"
            ) config.ghaf.networking.hosts.entries;
            hostAddress = head (map (x: x.ip) hostEntry);
            powerControl = pkgs.callPackage ../../../packages/powercontrol { };
            privateSshKeyPath = config.ghaf.security.sshKeys.sshKeyPath;
          in
          [
            {
              # The SPKI fingerprint is calculated like this:
              # $ openssl x509 -noout -in mitmproxy-ca-cert.pem -pubkey | openssl asn1parse -noout -inform pem -out public.key
              # $ openssl dgst -sha256 -binary public.key | openssl enc -base64
              name = "Chromium";
              path =
                if isIdsvmEnabled then
                  "${pkgs.openssh}/bin/ssh -i ${privateSshKeyPath} -o StrictHostKeyChecking=no chromium-vm run-waypipe chromium --enable-features=UseOzonePlatform --ozone-platform=wayland --user-data-dir=/home/${config.ghaf.users.accounts.user}/.config/chromium/Default --ignore-certificate-errors-spki-list=Bq49YmAq1CG6FuBzp8nsyRXumW7Dmkp7QQ/F82azxGU="
                else
                  "${pkgs.openssh}/bin/ssh -i ${privateSshKeyPath} -o StrictHostKeyChecking=no chromium-vm run-waypipe chromium --enable-features=UseOzonePlatform --ozone-platform=wayland";
              icon = "${pkgs.icon-pack}/chromium.svg";
            }

            {
              name = "Trusted Browser";
              path =
                if isIdsvmEnabled then
                  "${pkgs.openssh}/bin/ssh -i ${privateSshKeyPath} -o StrictHostKeyChecking=no business-vm run-waypipe chromium --enable-features=UseOzonePlatform --ozone-platform=wayland --user-data-dir=/home/${config.ghaf.users.accounts.user}/.config/chromium/Default --ignore-certificate-errors-spki-list=Bq49YmAq1CG6FuBzp8nsyRXumW7Dmkp7QQ/F82azxGU="
                else
                  "${pkgs.openssh}/bin/ssh -i ${privateSshKeyPath} -o StrictHostKeyChecking=no business-vm run-waypipe chromium --enable-features=UseOzonePlatform --ozone-platform=wayland";
              icon = "${pkgs.icon-pack}/thorium-browser.svg";
            }
            # TODO must enable the waypipe to support more than one app in a VM
            {
              name = "VPN";
              path = "${pkgs.openssh}/bin/ssh -i ${privateSshKeyPath} -o StrictHostKeyChecking=no business-vm run-waypipe gpclient -platform wayland";
              icon = "${pkgs.icon-pack}/yast-vpn.svg";
            }

            {
              name = "Microsoft Outlook";
              path = "${pkgs.openssh}/bin/ssh -i ${privateSshKeyPath} -o StrictHostKeyChecking=no business-vm run-waypipe chromium --enable-features=UseOzonePlatform --ozone-platform=wayland --app=https://outlook.office.com/mail/";
              icon = "${pkgs.icon-pack}/ms-outlook.svg";
            }
            {
              name = "Microsoft 365";
              path = "${pkgs.openssh}/bin/ssh -i ${privateSshKeyPath} -o StrictHostKeyChecking=no business-vm run-waypipe chromium --enable-features=UseOzonePlatform --ozone-platform=wayland --app=https://microsoft365.com";
              icon = "${pkgs.icon-pack}/microsoft-365.svg";
            }
            {
              name = "Teams";
              path = "${pkgs.openssh}/bin/ssh -i ${privateSshKeyPath} -o StrictHostKeyChecking=no business-vm run-waypipe chromium --enable-features=UseOzonePlatform --ozone-platform=wayland --app=https://teams.microsoft.com";
              icon = "${pkgs.icon-pack}/teams-for-linux.svg";
            }

            {
              name = "GALA";
              path = "${pkgs.openssh}/bin/ssh -i ${privateSshKeyPath} -o StrictHostKeyChecking=no gala-vm run-waypipe gala --enable-features=UseOzonePlatform --ozone-platform=wayland";
              icon = "${pkgs.icon-pack}/distributor-logo-android.svg";
            }

            {
              name = "PDF Viewer";
              path = "${pkgs.openssh}/bin/ssh -i ${privateSshKeyPath} -o StrictHostKeyChecking=no zathura-vm run-waypipe zathura";
              icon = "${pkgs.icon-pack}/document-viewer.svg";
            }

            {
              name = "Element";
              path = "${pkgs.openssh}/bin/ssh -i ${privateSshKeyPath} -o StrictHostKeyChecking=no element-vm run-waypipe element-desktop --enable-features=UseOzonePlatform --ozone-platform=wayland";
              icon = "${pkgs.icon-pack}/element-desktop.svg";
            }

            {
              name = "AppFlowy";
              path = "${pkgs.openssh}/bin/ssh -i ${privateSshKeyPath} -o StrictHostKeyChecking=no appflowy-vm run-waypipe appflowy";
              icon = "${pkgs.appflowy}/opt/data/flutter_assets/assets/images/flowy_logo.svg";
            }

            {
              name = "Network Settings";
              path = "${pkgs.nm-launcher}/bin/nm-launcher";
              icon = "${pkgs.icon-pack}/preferences-system-network.svg";
            }

            {
              name = "Shutdown";
              path = "${powerControl.makePowerOffCommand {
                inherit hostAddress;
                inherit privateSshKeyPath;
              }}";
              icon = "${pkgs.icon-pack}/system-shutdown.svg";
            }

            {
              name = "Reboot";
              path = "${powerControl.makeRebootCommand {
                inherit hostAddress;
                inherit privateSshKeyPath;
              }}";
              icon = "${pkgs.icon-pack}/system-reboot.svg";
            }

            # Temporarly disabled as it fails to turn off display when suspended
            # {
            #   name = "Suspend";
            #   path = "${powerControl.makeSuspendCommand {
            #     inherit hostAddress;
            #     inherit privateSshKeyPath;
            #   }}";
            #   icon = "${pkgs.icon-pack}/system-suspend.svg";
            # }

            # Temporarly disabled as it doesn't work at all
            # {
            #   name = "Hibernate";
            #   path = "${powerControl.makeHibernateCommand {
            #     inherit hostAddress;
            #     inherit privateSshKeyPath;
            #   }}";
            #   icon = "${pkgs.icon-pack}/system-suspend-hibernate.svg";
            # }
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
