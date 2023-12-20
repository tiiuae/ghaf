# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  configHost = config;
  vmName = "ids-vm";
  macAddress = "02:00:00:01:01:02";
  networkName = "ethint0";

  idsvmBaseConfiguration = {
    imports = [
      ({lib, ...}: {
        ghaf = {
          users.accounts.enable = lib.mkDefault configHost.ghaf.users.accounts.enable;
          development = {
            # NOTE: SSH port also becomes accessible on the network interface
            #       that has been passed through to NetVM
            ssh.daemon.enable = lib.mkDefault configHost.ghaf.development.ssh.daemon.enable;
            debug.tools.enable = lib.mkDefault configHost.ghaf.development.debug.tools.enable;
          };
        };

        system.stateVersion = lib.trivial.release;

        nixpkgs.buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
        nixpkgs.hostPlatform.system = configHost.nixpkgs.hostPlatform.system;

        microvm.hypervisor = "qemu";

        environment.systemPackages = [
          pkgs.mitmproxy
          pkgs.snort
          pkgs.tcpdump
        ];

        networking = {
          enableIPv6 = false;
          firewall.allowedTCPPorts = [22 8080 8081]; # SSH, mitmproxy, mitmweb
          firewall.allowedUDPPorts = [67];
          useNetworkd = true;
          nat = {
            enable = true;
            internalInterfaces = [networkName];

            # Redirect http(s) traffic to mitmproxy.
            extraCommands = ''
              iptables -t nat -A PREROUTING -i ethint0 -p tcp --dport 80 -j REDIRECT --to-port 8080
              iptables -t nat -A PREROUTING -i ethint0 -p tcp --dport 443 -j REDIRECT --to-port 8080
            '';
          };
        };

        # Here we add default CA keypair and corresponding self-signed certificate
        # for mitmproxy in different formats. These should be, of course, randomly and
        # securely generated and stored for each instance, but for development purposes
        # we use these fixed ones.
        environment.etc = {
          "mitmproxy/mitmproxy-ca-cert.cer".source = ./mitmproxy-ca/mitmproxy-ca-cert.cer;
          "mitmproxy/mitmproxy-ca-cert.p12".source = ./mitmproxy-ca/mitmproxy-ca-cert.p12;
          "mitmproxy/mitmproxy-ca-cert.pem".source = ./mitmproxy-ca/mitmproxy-ca-cert.pem;
          "mitmproxy/mitmproxy-ca.pem".source = ./mitmproxy-ca/mitmproxy-ca.pem;
          "mitmproxy/mitmproxy-ca.p12".source = ./mitmproxy-ca/mitmproxy-ca.p12;
          "mitmproxy/mitmproxy-dhparam.pem".source = ./mitmproxy-ca/mitmproxy-dhparam.pem;
        };

        systemd.services."mitmweb-server" = let
          mitmwebScript = pkgs.writeShellScriptBin "mitmweb-server" ''
            ${pkgs.mitmproxy}/bin/mitmweb --web-host localhost --web-port 8081 --set confdir=/etc/mitmproxy
          '';
        in {
          enable = true;
          description = "Run mitmweb to establish web interface for mitmproxy";
          path = [mitmwebScript];
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            Type = "simple";
            StandardOutput = "journal";
            StandardError = "journal";
            ExecStart = "${mitmwebScript}/bin/mitmweb-server";
            Restart = "on-failure";
            RestartSec = "1";
          };
        };

        microvm.interfaces = [
          {
            type = "tap";
            # The interface names must have maximum length of 15 characters
            id = "tap-${vmName}";
            mac = macAddress;
          }
        ];

        systemd.network = {
          enable = true;
          # Set internal network's interface name to networkName
          links."10-${networkName}" = {
            matchConfig.PermanentMACAddress = macAddress;
            linkConfig.Name = networkName;
          };
          networks."10-${networkName}" = {
            matchConfig.MACAddress = macAddress;
            DHCP = "no";
            gateway = ["192.168.100.1"];
            addresses = [
              {
                addressConfig.Address = "192.168.100.4/24";
              }
              {
                # IP-address for debugging subnet
                addressConfig.Address = "192.168.101.4/24";
              }
            ];
            linkConfig.RequiredForOnline = "routable";
            linkConfig.ActivationPolicy = "always-up";
          };
        };

        services.resolved.dnssec = "false";

        microvm = {
          optimize.enable = true;
          shares = [
            {
              tag = "ro-store";
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
            }
          ];
          writableStoreOverlay = lib.mkIf config.ghaf.development.debug.tools.enable "/nix/.rw-store";
        };

        imports = import ../../module-list.nix;
      })
    ];
  };
  cfg = config.ghaf.virtualization.microvm.idsvm;
in {
  options.ghaf.virtualization.microvm.idsvm = {
    enable = lib.mkEnableOption "IDSVM";

    extraModules = lib.mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        IDSVM's NixOS configuration.
      '';
      default = [];
    };
  };

  config = lib.mkIf cfg.enable {
    microvm.vms."${vmName}" = {
      autostart = true;
      config =
        idsvmBaseConfiguration
        // {
          imports =
            idsvmBaseConfiguration.imports
            ++ cfg.extraModules;
        };
      specialArgs = {inherit lib;};
    };
  };
}
