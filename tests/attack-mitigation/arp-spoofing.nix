# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Tests ghaf.firewall.attack-mitigation.arpSpoofing on a real bridge.
#
# The bridge and the guests come from ./common.nix. macIpSpoofing is off on both
# nodes, so only the ARP rules differ between them. The `unprotected` node shows
# that the flood and the poisoning work when nothing drops ARP.
#
#   node: protected                     node: unprotected
#   (arpSpoofing on)                    (arpSpoofing off)
#  ┌───────────────────────────┐      ┌───────────────────────────┐
#  │ virbr0 + ARP drop rules   │      │ virbr0, no rules          │
#  │  ├ tap-net-vm    → netns  │      │  ├ tap-net-vm    → netns  │
#  │  ├ tap-admin-vm  → netns  │      │  ├ tap-admin-vm  → netns  │
#  │  ├ tap-gui-vm    → netns  │      │  ├ tap-gui-vm    → netns  │
#  │  └ tap-chrome-vm → netns  │      │  └ tap-chrome-vm → netns  │
#  └───────────────────────────┘      └───────────────────────────┘
{ pkgs, lib, ... }:
let
  common = import ./common.nix { inherit pkgs lib; };

  # Broadcasts ARP requests from one guest and prints how many the receiver saw.
  arpProbe = pkgs.writeShellApplication {
    name = "arp-probe";
    runtimeInputs = [
      pkgs.iproute2
      pkgs.python3
    ];
    text = ''
      sender=$1 receiver=$2 count=$3 claimed=$4 target=$5
      if [ "$receiver" = host ]; then
        listen=(python3)
        iface=virbr0
      else
        listen=(ip netns exec "$receiver" python3)
        iface=ethint0
      fi
      seen=$(mktemp)
      "''${listen[@]}" -c '
      import socket, sys, time
      claimed = socket.inet_aton(sys.argv[2])
      s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(0x0806))
      s.bind((sys.argv[1], 0))
      deadline = time.time() + 3
      n = 0
      while time.time() < deadline:
          s.settimeout(max(deadline - time.time(), 0.01))
          try:
              frame = s.recv(128)
          except OSError:
              break
          # An ARP request whose sender address is the claimed one.
          if frame[20:22] == b"\x00\x01" and frame[28:32] == claimed:
              n += 1
      print(n)
      ' "$iface" "$claimed" >"$seen" &
      sleep 0.5
      ip netns exec "$sender" python3 -c '
      import socket, sys
      count, claimed, target = int(sys.argv[1]), sys.argv[2], sys.argv[3]
      mac = bytes.fromhex(open("/sys/class/net/ethint0/address").read().strip().replace(":", ""))
      s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
      s.bind(("ethint0", 0))
      frame = (
          b"\xff" * 6 + mac + b"\x08\x06"
          + b"\x00\x01\x08\x00\x06\x04\x00\x01"
          + mac + socket.inet_aton(claimed)
          + b"\x00" * 6 + socket.inet_aton(target)
      )
      for _ in range(count):
          s.send(frame)
      ' "$count" "$claimed" "$target"
      wait
      cat "$seen"
    '';
  };

  mkNode = arpSpoofing: {
    imports = [
      (common.mkNode {
        inherit arpSpoofing;
        macIpSpoofing = false;
      })
    ];
    environment.systemPackages = [ arpProbe ];
  };
in
# Enabled anywhere but the host, the option must fail the build by name.
assert lib.assertMsg (lib.any (lib.hasInfix "only apply on the host") (
  common.guestFailures (mkNode true)
)) "arpSpoofing enabled outside the host did not trip its assertion";
pkgs.testers.nixosTest {
  name = "attack-mitigation-arp-spoofing";

  nodes.protected = mkNode true;
  nodes.unprotected = mkNode false;

  testScript = ''
    import re

    ${common.prelude}
    FLOOD = 200

    # `sender` broadcasts `count` ARP requests that claim to come from `claimed`
    # and ask for `target`. Returns how many of them `receiver` saw.
    def arp_probe(machine, sender, receiver, count, claimed, target):
        return int(machine.succeed(f"arp-probe {sender} {receiver} {count} {claimed} {target}"))

    def neighbour(machine, vm, addr):
        return machine.succeed(f"ip -n {vm} neigh show {addr}")

    # Frames the ARP rules of one chain have dropped so far.
    def arp_drops(machine, chain):
        counters = machine.succeed(f"ebtables -L {chain} --Lc")
        return sum(int(n) for n in re.findall(r"pcnt = (\d+)", counters))

    start_all()
    for machine in [protected, unprotected]:
        bring_up(machine)

    # 1. Test: control. With nothing dropping ARP, a flood from gui-vm reaches
    # another guest and the host in full.
    with subtest("unprotected: a guest's ARP reaches the host and other guests"):
        assert arp_probe(unprotected, "gui-vm", "chrome-vm", FLOOD, GUI, CHROME) == FLOOD
        assert arp_probe(unprotected, "gui-vm", "host", FLOOD, GUI, HOST) == FLOOD

    # 2. Test: control. A guest that has to learn an address by ARP can be told
    # a false one: gui-vm announces admin-vm's address with its own MAC.
    with subtest("unprotected: a guest can poison another guest's ARP table"):
        # chrome-vm drops its static entry for admin-vm and resolves it by ARP.
        unprotected.succeed(f"ip -n chrome-vm neigh del {ADMIN} dev ethint0")
        unprotected.succeed(ping("chrome-vm", ADMIN))
        assert ADMIN_MAC in neighbour(unprotected, "chrome-vm", ADMIN)
        arp_probe(unprotected, "gui-vm", "chrome-vm", 3, ADMIN, CHROME)
        assert GUI_MAC in neighbour(unprotected, "chrome-vm", ADMIN)

    # 3. Test: the same flood reaches nobody, and the drop rules account for it.
    with subtest("an ARP flood from a guest is dropped at the bridge"):
        forwarded, delivered = arp_drops(protected, "FORWARD"), arp_drops(protected, "INPUT")
        assert arp_probe(protected, "gui-vm", "chrome-vm", FLOOD, GUI, CHROME) == 0
        assert arp_probe(protected, "gui-vm", "host", FLOOD, GUI, HOST) == 0
        assert arp_drops(protected, "FORWARD") - forwarded >= 2 * FLOOD
        assert arp_drops(protected, "INPUT") - delivered >= 2 * FLOOD

    # 4. Test: the false announcement never arrives, so there is nothing to learn.
    with subtest("a guest cannot poison another guest's ARP table"):
        protected.succeed(f"ip -n chrome-vm neigh del {ADMIN} dev ethint0")
        arp_probe(protected, "gui-vm", "chrome-vm", 3, ADMIN, CHROME)
        assert GUI_MAC not in neighbour(protected, "chrome-vm", ADMIN)

    # 5. Test: guests rely on their static entries. With one, traffic flows; the
    # guest that lost its entry cannot get it back by ARP.
    with subtest("static entries carry the traffic, ARP cannot replace them"):
        protected.succeed(ping("gui-vm", CHROME))
        protected.succeed(ping("gui-vm", HOST))
        protected.fail(ping("chrome-vm", ADMIN))
        protected.succeed(f"ip -n chrome-vm neigh replace {ADMIN} lladdr {ADMIN_MAC} dev ethint0 nud permanent")
        protected.succeed(ping("chrome-vm", ADMIN))
  '';
}
