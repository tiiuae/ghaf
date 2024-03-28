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

  netvmAdditionalFirewallConfig = {
    # ip forwarding functionality is needed for iptables
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

    # https://github.com/troglobit/smcroute?tab=readme-ov-file#linux-requirements
    boot.kernelPatches = [
      {
        name = "multicast-routing-config";
        patch = null;
        extraStructuredConfig = with lib.kernel; {
          IP_MULTICAST = yes;
          IP_MROUTE = yes;
          IP_PIMSM_V1 = yes;
          IP_PIMSM_V2 = yes;
          IP_MROUTE_MULTIPLE_TABLES = yes; # For multiple routing tables
        };
      }
    ];
    environment.systemPackages = [pkgs.smcroute];
    systemd.services."smcroute" = {
      description = "Static Multicast Routing daemon";
      # after = [ "network-online.target" ];
      # wants = [ "network-online.target" ];
      bindsTo = ["sys-subsystem-net-devices-wlp0s5f0.device"];
      after = ["sys-subsystem-net-devices-wlp0s5f0.device"];
      preStart = ''
              configContent=$(cat <<EOF
        mgroup from wlp0s5f0 group 239.0.0.114
        mgroup from ethint0 group 239.0.0.114
        mroute from wlp0s5f0 group 239.0.0.114 to ethint0
        mroute from ethint0 group 239.0.0.114 to wlp0s5f0
        EOF
        )
        filePath="/etc/smcroute.conf"
        touch $filePath
          chmod 200 $filePath
          echo "$configContent" > $filePath
          chmod 400 $filePath
      '';

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.smcroute}/sbin/smcrouted -n -s -f /etc/smcroute.conf";
        #TODO sudo setcap cap_net_admin=ep ${pkgs.smcroute}/sbin/smcroute
        User = "root";
        # Automatically restart service when it exits.
        Restart = "always";
        # Wait a second before restarting.
        RestartSec = "1s";
      };
      wantedBy = ["multi-user.target"];
    };

    networking = {
      firewall.enable = true;
      firewall.extraCommands = "
        # TODO interface names,ip addresses should be defined by nix
        # Set the default policies
          iptables -P INPUT DROP    
          iptables -P FORWARD DROP
          iptables -P OUTPUT ACCEPT 

        # Allow loopback traffic
          iptables -A INPUT -i lo -j ACCEPT
          iptables -A OUTPUT -o lo -j ACCEPT

        # Forward incoming TCP traffic on port 49000 to internal network(element-vm)
          iptables -t nat -A PREROUTING -i wlp0s5f0 -p tcp --dport 49000 -j DNAT --to-destination  192.168.100.253:49000

        # Enable NAT for outgoing traffic
          iptables -t nat -A POSTROUTING -o wlp0s5f0 -p tcp --dport 49000 -j MASQUERADE

        # Enable NAT for outgoing traffic
          iptables -t nat -A POSTROUTING -o wlp0s5f0 -p tcp --sport 49000 -j MASQUERADE

        # Enable NAT for outgoing udp multicast traffic
        iptables -t nat -A POSTROUTING -o wlp0s5f0 -p udp -d 239.0.0.114 --dport 60606 -j MASQUERADE

        # ttl value must be set to 1 for avoiding multicast looping 
        # https://github.com/troglobit/smcroute?tab=readme-ov-file#usage
        iptables -t mangle -A PREROUTING -i wlp0s5f0 -d 239.0.0.114 -j TTL --ttl-inc 1
        iptables -t mangle -A PREROUTING -i ethint0 -d 239.0.0.114 -j TTL --ttl-inc 1


        # Log accepted packets
          iptables -A FORWARD -j ACCEPT
      ";
    };
  };

  netvmAdditionalConfig = {
    # Add the waypipe-ssh public key to the microvm
    microvm = {
      shares = [
        {
          tag = configH.ghaf.security.sshKeys.waypipeSshPublicKeyName;
          source = configH.ghaf.security.sshKeys.waypipeSshPublicKeyDir;
          mountPoint = configH.ghaf.security.sshKeys.waypipeSshPublicKeyDir;
        }
      ];
    };
    fileSystems.${configH.ghaf.security.sshKeys.waypipeSshPublicKeyDir}.options = ["ro"];

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
    # noXlibs=false; needed for NetworkManager stuff
    environment.noXlibs = false;
    environment.etc."NetworkManager/system-connections/Wifi-1.nmconnection" = {
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
    # Waypipe-ssh key is used here to create keys for ssh tunneling to forward D-Bus sockets.
    # SSH is very picky about to file permissions and ownership and will
    # accept neither direct path inside /nix/store or symlink that points
    # there. Therefore we copy the file to /etc/ssh/get-auth-keys (by
    # setting mode), instead of symlinking it.
    environment.etc.${configH.ghaf.security.sshKeys.getAuthKeysFilePathInEtc} = import ./getAuthKeysSource.nix {
      inherit pkgs;
      config = configH;
    };
    # Add simple wi-fi connection helper
    environment.systemPackages = lib.mkIf configH.ghaf.profiles.debug.enable [pkgs.wifi-connector-nmcli pkgs.tcpdump];

    services.openssh = configH.ghaf.security.sshKeys.sshAuthorizedKeysCommand;

    time.timeZone = "Asia/Dubai";
  };
in [./sshkeys.nix netvmPCIPassthroughModule netvmAdditionalConfig netvmAdditionalFirewallConfig]
