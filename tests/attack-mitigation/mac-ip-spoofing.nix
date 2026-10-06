# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Tests ghaf.firewall.attack-mitigation.macIpSpoofing on a real bridge.
#
# The bridge and the guests come from ./common.nix.
# The `unprotected` node runs the same attacks without the option: if they stop
# succeeding there, the test has lost the ability to see the bug.
#
#   node: protected                     node: unprotected
#   (macIpSpoofing on)                  (macIpSpoofing off)
#  ┌───────────────────────────┐      ┌───────────────────────────┐
#  │ virbr0 + rules + FDB      │      │ virbr0, ARP rule only     │
#  │  ├ tap-net-vm    → netns  │      │  ├ tap-net-vm    → netns  │
#  │  ├ tap-admin-vm  → netns  │      │  ├ tap-admin-vm  → netns  │
#  │  ├ tap-gui-vm    → netns  │      │  ├ tap-gui-vm    → netns  │
#  │  └ tap-chrome-vm → netns  │      │  └ tap-chrome-vm → netns  │
#  └───────────────────────────┘      └───────────────────────────┘
{ pkgs, lib, ... }:
let
  common = import ./common.nix { inherit pkgs lib; };
  # A MAC no guest owns, so the bridge has no FDB entry for it.
  unknownMac = "02:ad:00:00:00:fe";

  # Sends unicast frames to `unknownMac` and prints how many the receiver saw.
  unknownUnicastProbe = pkgs.writeShellApplication {
    name = "unknown-unicast-probe";
    runtimeInputs = [
      pkgs.iproute2
      pkgs.python3
    ];
    text = ''
      sender=$1 receiver=$2 count=$3
      seen=$(mktemp)
      ip netns exec "$receiver" python3 -c '
      import socket, sys, time
      dst = bytes.fromhex(sys.argv[1].replace(":", ""))
      s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(0x88B5))
      s.bind(("ethint0", 0))
      deadline = time.time() + 3
      n = 0
      while time.time() < deadline:
          s.settimeout(max(deadline - time.time(), 0.01))
          try:
              frame = s.recv(128)
          except OSError:
              break
          if frame[0:6] == dst:
              n += 1
      print(n)
      ' "${unknownMac}" >"$seen" &
      sleep 0.5
      ip netns exec "$sender" python3 -c '
      import socket, sys
      dst = bytes.fromhex(sys.argv[1].replace(":", ""))
      src = bytes.fromhex(open("/sys/class/net/ethint0/address").read().strip().replace(":", ""))
      s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
      s.bind(("ethint0", 0))
      # 0x88B5 is the local experimental EtherType: not IP, so only the MAC rule sees it.
      for _ in range(int(sys.argv[2])):
          s.send(dst + src + b"\x88\xb5" + bytes(46))
      ' "${unknownMac}" "$count"
      wait
      cat "$seen"
    '';
  };

  mkNode = macIpSpoofing: {
    imports = [
      (common.mkNode {
        arpSpoofing = true;
        inherit macIpSpoofing;
      })
    ];
    environment.systemPackages = [ unknownUnicastProbe ];
  };
in
# Enabled anywhere but the host, the option must fail the build by name.
assert lib.assertMsg (lib.any (lib.hasInfix "only apply on the host") (
  common.guestFailures (mkNode true)
)) "macIpSpoofing enabled outside the host did not trip its assertion";
# A guest with IPv6 on would lose it at the bridge without a word.
assert lib.assertMsg (lib.any (lib.hasInfix "no guest may set networking.enableIPv6") (
  common.failures {
    imports = [ (mkNode true) ];
    microvm.vms.gui-vm.evaluatedConfig.config.networking.enableIPv6 = true;
  }
)) "macIpSpoofing accepted a guest with IPv6 enabled";
pkgs.testers.nixosTest {
  name = "attack-mitigation-mac-ip-spoofing";

  nodes.protected = mkNode true;
  nodes.unprotected = mkNode false;

  testScript = ''
    ${common.prelude}
    OUTSIDE = "8.8.8.8"

    # The bridge must not learn on the guest's tap, and must hold its MAC there.
    def pinned(machine, vm, mac):
        machine.succeed(f"bridge -d link show dev tap-{vm} | grep -q 'learning off'")
        machine.succeed(f"bridge -d link show dev tap-{vm} | grep -q ' flood off'")
        machine.succeed(f"bridge fdb show br virbr0 | grep -i '{mac} dev tap-{vm} master virbr0 static'")

    start_all()
    for machine in [protected, unprotected]:
        bring_up(machine)
        # An address net-vm can send from as if it were forwarding from outside.
        machine.succeed(f"ip -n net-vm addr add {OUTSIDE}/32 dev lo")

    # 1. Test: gui-vm is the compromised guest, admin-vm the one it poses as.
    # Both forms of the attack must succeed here and fail on `protected` below.
    with subtest("unprotected: a guest can pose as another guest"):
        # gui-vm takes admin-vm's MAC and address, as the report's steps do.
        unprotected.succeed(f"impersonate gui-vm {ADMIN_MAC} {ADMIN}")
        # The host answers it as admin-vm.
        unprotected.succeed(ping("gui-vm", HOST))
        # Traffic meant for admin-vm now lands on gui-vm: the bridge learned the MAC there.
        assert probe(unprotected, "host", "gui-vm", ADMIN) == HOST
        # A third guest sees its datagram as coming from admin-vm.
        assert probe(unprotected, "gui-vm", "chrome-vm", CHROME) == ADMIN
        # gui-vm goes back to its own MAC and keeps only admin-vm's address.
        unprotected.succeed(f"impersonate gui-vm {GUI_MAC} {ADMIN}")
        assert probe(unprotected, "gui-vm", "chrome-vm", CHROME) == ADMIN

    # 2. Test: the same attacks must fail on `protected`, and the bridge must keep
    with subtest("each guest's MAC is pinned to its tap"):
        pinned(protected, "gui-vm", GUI_MAC)
        pinned(protected, "admin-vm", ADMIN_MAC)

    # 3. Test: Every guest still reaches the host and the others from its own address.
    with subtest("legitimate traffic passes"):
        protected.succeed(ping("gui-vm", ADMIN))
        protected.succeed(ping("chrome-vm", NET))
        assert probe(protected, "gui-vm", "chrome-vm", CHROME) == GUI
        assert probe(protected, "gui-vm", "host", HOST) == GUI
        assert probe(protected, "net-vm", "chrome-vm", CHROME) == NET

    # 4. Test: net-vm forwards replies from the internet, so foreign sources must pass.
    with subtest("a gateway may forward outside sources, not another guest's"):
        assert probe(protected, "net-vm", "chrome-vm", CHROME, OUTSIDE) == OUTSIDE
        # Let net-vm send from admin-vm's address; the bridge must drop it.
        protected.succeed(f"ip -n net-vm addr add {ADMIN}/32 dev lo")
        assert probe(protected, "net-vm", "chrome-vm", CHROME, ADMIN) == "-"
        protected.succeed(f"ip -n net-vm addr del {ADMIN}/32 dev lo")

    # 5. Test: attack -> gui-vm takes admin-vm's MAC and address.
    with subtest("a guest cannot take another guest's MAC and address"):
        protected.succeed(f"impersonate gui-vm {ADMIN_MAC} {ADMIN}")
        # Neither the host nor another guest receives anything from it.
        protected.fail(ping("gui-vm", HOST))
        assert probe(protected, "gui-vm", "host", HOST) == "-"
        assert probe(protected, "gui-vm", "chrome-vm", CHROME) == "-"
        # The victim still gets its own traffic and gui-vm gets no copy of it:
        # the FDB entry did not move and the frame is not flooded.
        assert probe(protected, "host", "admin-vm", ADMIN) == HOST
        assert probe(protected, "host", "gui-vm", ADMIN) == "-"

    # 6. Test: attack: gui-vm keeps its own MAC and uses admin-vm's address.
    with subtest("a guest cannot use another guest's address with its own MAC"):
        protected.succeed(f"impersonate gui-vm {GUI_MAC} {ADMIN}")
        assert probe(protected, "gui-vm", "host", HOST) == "-"
        assert probe(protected, "gui-vm", "chrome-vm", CHROME) == "-"
        # Back to its own MAC and address: the attempt left nothing broken.
        protected.succeed(f"impersonate gui-vm {GUI_MAC} {GUI}")
        protected.succeed(ping("gui-vm", ADMIN))

    # 7. Test: Guests run without IPv6, so the bridge drops it. `unprotected` shows the
    # ping itself is valid.
    with subtest("IPv6 does not cross the bridge"):
        for machine in [protected, unprotected]:
            for vm, mac, addr in [("gui-vm", GUI_MAC, GUI), ("chrome-vm", CHROME_MAC, CHROME)]:
                machine.succeed(f"ip netns exec {vm} sysctl -qw net.ipv6.conf.all.disable_ipv6=0")
                # Bounces the link, which is when the kernel assigns the link-local address.
                machine.succeed(f"impersonate {vm} {mac} {addr}")
            machine.sleep(3)
        v6 = "ip netns exec gui-vm ping -6 -c1 -W2 $(ip -n chrome-vm -6 -o addr show dev ethint0 scope link | awk '{print $4}' | cut -d/ -f1)%ethint0"
        unprotected.succeed(v6)
        protected.fail(v6)

    # networkd manages the taps too and restarts on a host switch; it must not
    # re-enable learning or drop the static entries.
    with subtest("restarting networkd keeps the pinning"):
        protected.succeed(ping("gui-vm", ADMIN))
        protected.succeed("systemctl restart systemd-networkd")
        protected.wait_until_succeeds("networkctl status tap-gui-vm | grep -q configured")
        pinned(protected, "gui-vm", GUI_MAC)
        protected.succeed(ping("gui-vm", ADMIN))

    # Every guest MAC is in the FDB, so a frame for an unknown one has no
    # recipient: the bridge drops it instead of copying it to every guest.
    with subtest("unknown unicast is not flooded to the guests"):
        assert int(unprotected.succeed("unknown-unicast-probe gui-vm chrome-vm 5")) == 5
        assert int(protected.succeed("unknown-unicast-probe gui-vm chrome-vm 5")) == 0

    # A VLAN priority tag (id 0) hides the IPv4 header from the address check,
    # and the receiver still treats the packet as untagged.
    with subtest("a VLAN tag does not carry a spoofed packet past the bridge"):
        for machine in [protected, unprotected]:
            machine.succeed(
                "ip -n gui-vm link add link ethint0 name v0 type vlan id 0",
                "ip -n gui-vm link set v0 up",
                f"ip -n gui-vm addr add {ADMIN}/32 dev v0",
                f"ip -n gui-vm route add {CHROME}/32 dev v0 src {ADMIN}",
                f"ip -n gui-vm neigh replace {CHROME} lladdr {CHROME_MAC} dev v0 nud permanent",
            )
        assert probe(unprotected, "gui-vm", "chrome-vm", CHROME, ADMIN) == ADMIN
        assert probe(protected, "gui-vm", "chrome-vm", CHROME, ADMIN) == "-"
  '';
}
