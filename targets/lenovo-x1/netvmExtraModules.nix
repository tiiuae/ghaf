# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  lib,
  pkgs,
  microvm,
  configH,
  ...
}: let
  netvmPCIPassthroughModule = {
    microvm.devices = lib.mkForce (
      builtins.map (d: {
        bus = "pci";
        inherit (d) path;
      })
      configH.ghaf.hardware.definition.network.pciDevices
    );
  };

  netvmAdditionalConfig = let
    externalNic = let
      firstPciWifiDevice = lib.head configH.ghaf.hardware.definition.network.pciDevices;
    in "${firstPciWifiDevice.name}";

    internalNic = let
      vmNetworking = import ../../modules/microvm/virtualization/microvm/common/vm-networking.nix {
        vmName = microvm.name;
        inherit (microvm) macAddress;
      };
    in "${lib.head vmNetworking.networking.nat.internalInterfaces}";

    elemen-vmIp = "192.168.100.253";
  in {
    # For WLAN firmwares
    hardware.enableRedistributableFirmware = true;

    networking = {
      # wireless is disabled because we use NetworkManager for wireless
      wireless.enable = lib.mkForce false;
      networkmanager = {
        enable = true;
        unmanaged = ["ethint0"];
      };
    };
    services = {
      dnsmasq.settings = {
        # set static IP for IDS-VM
        dhcp-host = lib.mkIf configH.ghaf.virtualization.microvm.idsvm.enable [
          "02:00:00:01:01:02,192.168.100.4,ids-vm,infinite"
        ];
        dhcp-option =
          if configH.ghaf.virtualization.microvm.idsvm.enable
          then [
            "option:router,192.168.100.4" # set IDS-VM as a default gw
            "option:dns-server,192.168.100.1"
          ]
          else [
            "option:router,192.168.100.1" # set NetVM as a default gw
            "option:dns-server,192.168.100.1"
          ];

        # DNS host record has been added for element-vm static ip
        host-record = "element-vm,element-vm.ghaf,${elemen-vmIp}";
      };

      openssh = configH.ghaf.security.sshKeys.sshAuthorizedKeysCommand;
    };

    environment = {
      # noXlibs=false; needed for NetworkManager stuff
      noXlibs = false;

      etc."NetworkManager/system-connections/Wifi-1.nmconnection" = {
        text = ''
          [connection]
          id=Wifi-1
          uuid=33679db6-4cde-11ee-be56-0242ac120002
          type=wifi
          [wifi]
          mode=infrastructure
          ssid=SSID_OF_NETWORK
          [wifi-security]
          key-mgmt=wpa-psk
          psk=WPA_PASSWORD
          [ipv4]
          method=auto
          [ipv6]
          method=disabled
          [proxy]
        '';
        mode = "0600";
      };

      # Add simple wi-fi connection helper
      systemPackages = lib.mkIf configH.ghaf.profiles.debug.enable [pkgs.wifi-connector-nmcli pkgs.tcpdump];
    };

    time.timeZone = "Asia/Dubai";

    ghaf.services.dendrite-pinecone = {
      enable = true;
      firewallConfig = true;
      externalNic = "${externalNic}";
      internalNic = "${internalNic}";
      serverIpAddr = "${elemen-vmIp}";
    };
  };
in [netvmPCIPassthroughModule netvmAdditionalConfig]
