# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  self,
  lib,
  ...
}:
let
  testConfig = "lenovo-x1-carbon-gen11-debug";
  cfg = self.nixosConfigurations.${testConfig};

  netvm-fw-cfg = cfg.config.microvm.vms.net-vm.config.config.networking.firewall;
  chromevm-fw-cfg = cfg.config.microvm.vms.chrome-vm.config.config.networking.firewall;
  addrs = {
    netvm-external = "192.168.1.2";
    externalvm = "192.168.1.20";
    netvm-internal = cfg.config.ghaf.networking.hosts.net-vm.ipv4;
    inherit (cfg.config.ghaf.networking.hosts.net-vm) chromevm;
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
    appVM =
      _:
      pkgs.lib.mkMerge [
        {
          inherit users security;
          virtualisation.vlans = [ 100 ];

          networking = {
            useDHCP = false;
            firewall = chromevm-fw-cfg;
            interfaces = {
              eth1.ipv4.addresses = lib.mkOverride 0 [
                {
                  address = addrs.chromevm;
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
      ];
    };
  };
  testScript = _: ''
    start_all()
    externalVM.wait_for_unit("default.target")
    netVM.wait_for_unit("default.target")
    appVM.wait_for_unit("default.target")


  '';
}
