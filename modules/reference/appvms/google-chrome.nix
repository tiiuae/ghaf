# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Google Chrome Browser App VM
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.reference.appvms.chrome;
  policyDir = "/etc/policies";

  chromeWrapper = pkgs.writeShellApplication {
    name = "chrome-wrapper";
    runtimeInputs = [
      pkgs.jq
      pkgs.google-chrome
    ];

    text = ''
      PREFS="$HOME/.config/google-chrome/Default/Preferences"
      mkdir -p "$(dirname "$PREFS")"

      # Create a minimal Preferences file if it doesn't exist
      if [ ! -f "$PREFS" ]; then
        echo '{}' > "$PREFS"
      fi

      # Enable system title bar and borders
      jq '
        .browser |= . // {}
        | .browser.custom_chrome_frame = false
      ' "$PREFS" > "$PREFS.tmp" && mv "$PREFS.tmp" "$PREFS"

      # Launch the browser
      google-chrome-stable --enable-features=UseOzonePlatform \
        --ozone-platform=wayland \
        --disable-gpu \
        ${config.ghaf.givc.idsExtraArgs} "$@"
    '';
  };
in
{
  _file = ./google-chrome.nix;

  options.ghaf.reference.appvms.chrome = {
    enable = lib.mkEnableOption "Google Chrome Browser App VM";
  };

  # Only configure when both enabled AND laptop-x86 profile is available
  # (reference appvms use laptop-x86.mkAppVm which doesn't exist on other profiles like Orin)
  config = lib.mkIf (cfg.enable && config.ghaf.profiles.laptop-x86.enable or false) {
    # DRY: Only enable, evaluatedConfig, and usbPassthrough at host level.
    # All values (name, mem, borderColor, applications, vtpm) are derived from vmDef.
    ghaf.virtualization.microvm.appvm.vms.chrome = {

      enable = lib.mkDefault true;

      usbPassthrough = [
        {
          description = "External Webcams for ChromeVM and BusinessVM";
          allowedVms = [
            "chrome-vm"
            "business-vm"
          ];
          allow = [
            {
              interfaceClass = 14;
              description = "Video (USB Webcams)";
            }
          ];
          # Ignore internal webcams since they are attached to business-vm
          deny = config.ghaf.reference.passthrough.usb.internalWebcams;
        }
      ];

      evaluatedConfig = config.ghaf.profiles.laptop-x86.mkAppVm {
        name = "chrome";
        packages = lib.optional config.ghaf.development.debug.tools.enable pkgs.alsa-utils;
        mem = 6144;
        vcpu = 4;
        borderColor = "#9C0000";
        ghafAudio.enable = lib.mkDefault true;
        vtpm.enable = lib.mkDefault true;
        yubiProxy = true;
        applications = [
          {
            # The SPKI fingerprint is calculated like this:
            # $ openssl x509 -noout -in mitmproxy-ca-cert.pem -pubkey | openssl asn1parse -noout -inform pem -out public.key
            # $ openssl dgst -sha256 -binary public.key | openssl enc -base64
            name = "google-chrome";
            desktopName = "Google Chrome";
            categories = [ "WebBrowser" ];
            description = "Isolated General Browsing";
            packages = [
              pkgs.google-chrome
              chromeWrapper
            ];
            icon = "google-chrome";
            exec = "chrome-wrapper";
            givcArgs = [
              "url"
              "flag"
            ];
            extraModules = [
              {
                imports = [ ../programs/google-chrome.nix ];
                ghaf = {
                  givc.policyClient = {
                    enable = true;
                    storePath = policyDir;
                  };
                  storagevm.directories = [
                    {
                      directory = policyDir;
                      user = config.ghaf.users.appUser.name;
                      group = config.ghaf.users.appUser.name;
                      mode = "0774";
                    }
                  ];
                  reference.programs.google-chrome.enable = lib.mkDefault true;
                  security.apparmor.enable = lib.mkDefault true;
                  xdgitems = {
                    enable = lib.mkDefault true;
                  };
                  xdghandlers.url = true;
                  firewall = {
                    updater.enable = true;
                    allowedUDPPorts = config.ghaf.reference.services.chromecast.udpPorts;
                    allowedTCPPorts = config.ghaf.reference.services.chromecast.tcpPorts;
                  };
                  givc.policyClient.policies.firewall-rules =
                    let
                      rulePath = "/etc/firewall/rules/fw.nft";
                    in
                    {
                      dest = rulePath;
                      updater = {
                        url = "https://raw.githubusercontent.com/tiiuae/ghaf-policies/deploy/vm-policies/firewall-rules/fw.nft";
                        poll_interval_secs = 300;
                      };

                      script = pkgs.writeShellScript "apply-nftables" ''
                        ${pkgs.nftables}/bin/nft -f ${rulePath}
                      '';
                    };
                  storagevm.maximumSize = 100 * 1024; # 100 GB space for google-chrome-vm
                };
              }
            ];
          }
        ]
        ++ (lib.optionals config.ghaf.virtualization.microvm.idsvm.mitmproxy.webUIEnabled [
          (
            let
              mitmWebUIport = config.ghaf.virtualization.microvm.idsvm.mitmproxy.webUIPort;
              mitmWebUIpswd = config.ghaf.virtualization.microvm.idsvm.mitmproxy.webUIPswd;
              idsvmIpAddr = config.ghaf.networking.hosts."ids-vm".ipv4;
            in
            {
              name = "MitmWebUI";
              desktopName = "MitmWebUI";
              description = "MitmWebUI";
              packages = [ pkgs.google-chrome ];
              icon = "nmap";
              exec = "${lib.getExe chromeWrapper} ${config.ghaf.givc.idsExtraArgs} --app=http://${toString idsvmIpAddr}:${toString mitmWebUIport}?token=${toString mitmWebUIpswd}";
              extraModules = [
                {
                  ghaf.firewall.allowedTCPPorts = mitmWebUIport;
                }
              ];
            }
          )
        ]);
        extraModules = [
          {
            microvm.devices = [ ];
            imports = [
              ../services/wireguard-gui/wireguard-gui.nix
            ];
            # Enable WireGuard GUI
            ghaf.reference.services.wireguard-gui = {
              enable = config.ghaf.reference.services.wireguard-gui;
              serverPorts = [
                51822
              ];
            };
          }
        ];
      };
    };
  };
}
