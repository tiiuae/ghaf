# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  self,
  lib,
  ...
}:
let
  basicRulesTest = import ./test_scripts/basic_rules.nix;
  testConfig = "lenovo-x1-carbon-gen11-debug";
  cfg = self.nixosConfigurations.${testConfig};

  netvm-fw-cfg = cfg.config.microvm.vms.net-vm.config.config.networking.firewall;

  internalvm-fw-cfg = cfg.config.networking.firewall;
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

pkgs.nixosTest {
  name = "firewall";

  nodes = {
    internalVM =
      _:
      pkgs.lib.mkMerge [
        {
          inherit users security;
          virtualisation.vlans = [ 100 ];

          networking = {
            useDHCP = false;
            firewall = internalvm-fw-cfg;
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
        }
      ];

    netVM = _: {

      inherit users security;
      virtualisation.vlans = [
        1 # 192.168.1.x
        100 # 192.168.100.x
      ];

      networking = {
        nat.enable = true;
        firewall = netvm-fw-cfg;
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
      externalVM.start(allow_reboot=True)
      netVM.start(allow_reboot=True)
      internalVM.start(allow_reboot=True)
      externalVM.wait_for_unit("default.target")
      netVM.wait_for_unit("default.target")
      internalVM.wait_for_unit("default.target")
      ${basicRulesTest { inherit nodes pkgs lib; }}

    '';
}
