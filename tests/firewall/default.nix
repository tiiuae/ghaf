# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  lib,
  ...
}:
let
  basicRulesTest = import ./test_scripts/basic_rules.nix;
  banRulesTest = import ./test_scripts/ban_rules.nix;
  fw-service-cfg = import ../../modules/common/systemd/hardened-configs/firewall.nix;
  addrs = {
    netvm-external = "192.168.1.2";
    externalvm = "192.168.1.20";
    netvm-internal = "192.168.100.1";
    internalvm = "192.168.100.105";
  };
  users.users.ghaf = {
    password = "ghaf";
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };
  security.sudo.extraRules = [
    {
      groups = [ "wheel" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
in

pkgs.testers.nixosTest {
  name = "firewall";

  nodes = {
    internalVM =
      _:

      {
        imports = [
          ../../modules/common/firewall
        ];
        inherit users security;
        virtualisation.vlans = [ 100 ];

        systemd.services.firewall.serviceConfig = fw-service-cfg;

        ghaf.firewall.enable = true;
        networking = {
          useDHCP = false;
          interfaces = {
            eth1.ipv4.addresses = lib.mkOverride 0 [
              {
                address = addrs.internalvm;
                prefixLength = 24;
              }
            ];
          };
          defaultGateway = addrs.netvm-internal;
          nftables.enable = false;
          enableIPv6 = false;

        };

        environment.systemPackages = [
          pkgs.toybox
          pkgs.tshark
          pkgs.tcpdump
        ];
      };

    netVM = _: {

      inherit users security;
      imports = [
        ../../modules/common/firewall
        ../../modules/common/security/fail2ban.nix
        ../../modules/common/security/ssh-tarpit
      ];
      virtualisation.vlans = [
        1 # 192.168.1.x
        100 # 192.168.100.x
      ];
      services.openssh.enable = true;
      systemd.services.firewall.serviceConfig = fw-service-cfg;
      ghaf = {
        security = {
          fail2ban = {
            enable = true;
            sshd-jail-fwmark = {
              enable = true;
              fwMarkNum = "70";
            };
          };
          ssh-tarpit = {
            enable = true;
            listenAddress = addrs.netvm-internal;
          };
        };
        firewall = {
          enable = true;
          allowedTCPPorts = [ 22 ];
          tcpBlacklistRules = [
            {
              port = 22;
              trackingSize = 200;
              burstNum = 10;
              maxPacketFreq = "5/second";
            }
          ];
        };
      };
      networking = {
        nat.enable = true;
        nftables.enable = false;
        nat.externalInterface = "eth1";
        interfaces = {
          eth1.ipv4.addresses = lib.mkOverride 0 [
            {
              address = addrs.netvm-external;
              prefixLength = 24;
            }
          ];
          eth2.ipv4.addresses = [
            {
              address = addrs.netvm-internal;
              prefixLength = 24;
            }
          ];
        };
        useDHCP = false;
        enableIPv6 = false;
      };

      systemd.services.test-config =
        let
          test-init = pkgs.writeShellApplication {
            name = "test_init";
            runtimeInputs = [
              pkgs.iptables
            ];
            text = ''
              # Log filtered packets (with TCP flags if protocol is TCP)
              iptables -I ghaf-fw-filter-drop -j LOG \
                --log-prefix "ghaf-fw-filter-drop: " \
                --log-level 4 \
                --log-tcp-options

              iptables -t mangle -I ghaf-fw-mangle-drop -j LOG \
                --log-prefix "ghaf-fw-mangle-drop: " \
                --log-level 4 \
                --log-tcp-options
              # for testing setup somehow it does not create nixos-fw.
              # But there is no issue for ghaf image
              iptables -t filter -A INPUT -j nixos-fw
            '';
          };
        in
        {
          description = "Additional test configs";
          after = [ "firewall.service" ];
          wants = [ "firewall.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${test-init}/bin/test_init";
          };
        };
      environment.systemPackages = [
        pkgs.toybox
        pkgs.tshark
        pkgs.tcpdump
      ];
    };
    externalVM = _: {
      inherit users security;

      virtualisation.vlans = [ 1 ];

      networking = {
        firewall.enable = false;
        interfaces = {
          eth1.ipv4.addresses = lib.mkOverride 0 [
            {
              address = addrs.externalvm;
              prefixLength = 24;
            }
          ];
        };
        useDHCP = false;
        enableIPv6 = false;
      };

      environment.systemPackages = [
        pkgs.toybox
        pkgs.tshark
        pkgs.nmap
        pkgs.hping
      ];
    };
  };
  testScript =
    { nodes, ... }:
    ''
      import re

      externalVM.start(allow_reboot=True)
      netVM.start(allow_reboot=True)
      internalVM.start(allow_reboot=True)
      externalVM.wait_for_unit("default.target")
      netVM.wait_for_unit("default.target")
      internalVM.wait_for_unit("default.target")
      ${basicRulesTest { inherit nodes pkgs lib; }}
      ${banRulesTest { inherit nodes pkgs lib; }}
    '';
}
