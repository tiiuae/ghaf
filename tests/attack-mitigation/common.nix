# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Shared scaffolding for the attack-mitigation tests: a host node with the real
# virbr0, and guests that are network namespaces joined to it by veth pairs
# named like the taps, so what is under test is what the module emits.
{ pkgs, lib }:
let
  subnet = "192.168.100";
  hostIdx = 2;
  vms = {
    net-vm = {
      idx = 1;
      gateway = true;
    };
    admin-vm.idx = 5;
    gui-vm.idx = 4;
    chrome-vm.idx = 102;
  };

  mkHost = idx: {
    mac = "02:ad:00:00:00:${lib.fixedWidthString 2 "0" (lib.toLower (lib.toHexString idx))}";
    ipv4 = "${subnet}.${toString idx}";
    ipv4SubnetPrefixLength = 24;
  };
  hosts = lib.mapAttrs (_: vm: mkHost vm.idx) vms // {
    ghaf-host = mkHost hostIdx;
  };

  # The module reads these from common.nix, hosts.nix and microvm.nix. Declaring
  # just what it touches keeps the test from evaluating a whole Ghaf host.
  stubs =
    { lib, ... }:
    {
      options = {
        ghaf = {
          type = lib.mkOption { type = lib.types.str; };
          networking.hosts = lib.mkOption { type = lib.types.attrsOf lib.types.attrs; };
          host.networking.bridgeNicName = lib.mkOption {
            type = lib.types.str;
            default = "virbr0";
          };
          givc.policyClient = {
            enable = lib.mkEnableOption "givc policy client (stub for tests)";
            policies = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = { };
            };
          };
        };
        microvm.vms = lib.mkOption {
          type = lib.types.attrsOf lib.types.attrs;
          default = { };
        };
      };
    };

  neighbours =
    run: dev:
    lib.concatStrings (
      lib.mapAttrsToList (
        _: host: "${run} neigh replace ${host.ipv4} lladdr ${host.mac} dev ${dev} nud permanent\n"
      ) hosts
    );

  # Stands in for microvm.nix's tap-up: creates the "guest" and its tap.
  tapUp = pkgs.writeShellApplication {
    name = "tap-up";
    runtimeInputs = [
      pkgs.iproute2
      pkgs.procps
    ];
    text = ''
      vm=$1
      case "$vm" in
      ${lib.concatStrings (
        lib.mapAttrsToList (
          name: _: "  ${name}) mac=${hosts.${name}.mac} addr=${hosts.${name}.ipv4} ;;\n"
        ) vms
      )}
        *) exit 1 ;;
      esac
      ip netns add "$vm"
      ip link add "tap-$vm" type veth peer name ethint0 netns "$vm"
      ip link set "tap-$vm" up
      ip netns exec "$vm" sysctl -qw net.ipv6.conf.all.disable_ipv6=1
      ip -n "$vm" link set lo up
      ip -n "$vm" link set ethint0 address "$mac"
      ip -n "$vm" addr add "$addr/24" dev ethint0
      ip -n "$vm" link set ethint0 up
      ${neighbours ''ip -n "$vm"'' "ethint0"}
      [ "$vm" = net-vm ] || ip -n "$vm" route add default via ${hosts.net-vm.ipv4}
    '';
  };

  # Gives a guest another MAC and address, as the report's reproduction does.
  impersonate = pkgs.writeShellApplication {
    name = "impersonate";
    runtimeInputs = [ pkgs.iproute2 ];
    text = ''
      vm=$1 mac=$2 addr=$3
      ip -n "$vm" link set ethint0 down
      ip -n "$vm" link set ethint0 address "$mac"
      ip -n "$vm" addr flush dev ethint0
      ip -n "$vm" addr add "$addr/24" dev ethint0
      ip -n "$vm" link set ethint0 up
      ${neighbours ''ip -n "$vm"'' "ethint0"}
    '';
  };

  # Sends one datagram and prints the source address the receiver saw, or "-".
  probe = pkgs.writeShellApplication {
    name = "probe";
    runtimeInputs = [
      pkgs.iproute2
      pkgs.python3
    ];
    text = ''
      sender=$1 receiver=$2 dst=$3 src=''${4:-}
      in_ns() {
        if [ "$1" = host ]; then
          shift
          "$@"
        else
          ip netns exec "$@"
        fi
      }
      seen=$(mktemp)
      in_ns "$receiver" python3 -c '
      import socket
      s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
      s.bind(("0.0.0.0", 9999))
      s.settimeout(2)
      try:
          print(s.recvfrom(64)[1][0])
      except OSError:
          print("-")
      ' >"$seen" &
      sleep 0.5
      in_ns "$sender" python3 -c '
      import socket, sys
      s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
      if sys.argv[2]:
          s.bind((sys.argv[2], 0))
      s.sendto(b"x", (sys.argv[1], 9999))
      ' "$dst" "$src" || true
      wait
      cat "$seen"
    '';
  };

  mkNode =
    { arpSpoofing, macIpSpoofing }:
    {
      imports = [
        ../../modules/common/firewall
        stubs
      ];

      # The stock kernel already has every module the firewall asks for; applying
      # the patches would only rebuild it.
      boot.kernelPatches = lib.mkForce [ ];

      ghaf = {
        type = "host";
        networking = { inherit hosts; };
        firewall = {
          enable = true;
          allowedUDPPorts = [ 9999 ];
          attack-mitigation = {
            arpSpoofing.enable = arpSpoofing;
            macIpSpoofing.enable = macIpSpoofing;
          };
        };
      };

      microvm.vms = lib.mapAttrs (_: vm: {
        evaluatedConfig.config.ghaf.virtualization.microvm.vm-networking = {
          enable = true;
          isGateway = vm.gateway or false;
        };
      }) vms;

      systemd.services."microvm-tap-interfaces@".serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${lib.getExe tapUp} %i";
      };

      # The bridge and the tap-* rule as modules/microvm/host/networking.nix has them.
      networking = {
        useNetworkd = true;
        useDHCP = false;
        nftables.enable = false;
        enableIPv6 = false;
      };
      systemd.network = {
        netdevs."10-virbr0" = {
          netdevConfig = {
            Kind = "bridge";
            Name = "virbr0";
            MACAddress = hosts.ghaf-host.mac;
          };
          bridgeConfig = {
            STP = false;
            ForwardDelaySec = 0;
          };
        };
        networks = {
          "10-virbr0" = {
            matchConfig.Name = "virbr0";
            addresses = [ { Address = "${hosts.ghaf-host.ipv4}/24"; } ];
            networkConfig.LinkLocalAddressing = "no";
            extraConfig = lib.concatStrings (
              lib.mapAttrsToList (_: host: ''
                [Neighbor]
                Address=${host.ipv4}
                LinkLayerAddress=${host.mac}
              '') hosts
            );
          };
          "11-vm-network" = {
            matchConfig.Name = "tap-*";
            networkConfig.Bridge = "virbr0";
          };
        };
      };

      environment.systemPackages = [
        impersonate
        probe
      ];
    };

  # Messages of the assertions a node fails, evaluated without building it.
  failures =
    node:
    map (a: a.message) (
      lib.filter (a: !a.assertion)
        (lib.nixosSystem {
          modules = [
            { nixpkgs.pkgs = pkgs; }
            node
          ];
        }).config.assertions
    );
in
{
  inherit hosts mkNode failures;

  # The same, with the node declared to be a guest rather than the host.
  guestFailures =
    node:
    failures {
      imports = [ node ];
      ghaf.type = lib.mkForce "system-vm";
    };

  # Python shared by the test scripts: the addresses and the basic helpers.
  prelude = ''
    VMS = ${builtins.toJSON (lib.attrNames vms)}
    HOST = "${hosts.ghaf-host.ipv4}"
    ADMIN = "${hosts.admin-vm.ipv4}"
    ADMIN_MAC = "${hosts.admin-vm.mac}"
    GUI = "${hosts.gui-vm.ipv4}"
    GUI_MAC = "${hosts.gui-vm.mac}"
    CHROME = "${hosts.chrome-vm.ipv4}"
    CHROME_MAC = "${hosts.chrome-vm.mac}"
    NET = "${hosts.net-vm.ipv4}"

    # Sends one datagram from `sender` to `dst` and returns the source address
    # `receiver` saw, or "-" if nothing arrived. `src` forces the source address.
    def probe(machine, sender, receiver, dst, src=""):
        return machine.succeed(f"probe {sender} {receiver} {dst} {src}").strip()

    def ping(vm, dst):
        return f"ip netns exec {vm} ping -c1 -W2 {dst}"

    # Brings a node to the starting point: rules loaded, bridge up, every guest
    # created and attached, and a route to the host that works.
    def bring_up(machine):
        machine.wait_for_unit("firewall.service")
        machine.wait_until_succeeds("ip link show virbr0")
        # Each unit creates one guest namespace and its tap.
        machine.succeed("systemctl start " + " ".join(f"microvm-tap-interfaces@{vm}" for vm in VMS))
        for vm in VMS:
            machine.wait_until_succeeds(f"bridge link show dev tap-{vm} | grep -q 'master virbr0'")
        machine.wait_until_succeeds(ping("gui-vm", HOST))
  '';
}
