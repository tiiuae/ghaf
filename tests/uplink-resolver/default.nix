# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Tests the uplink resolver's state machine.
#
# The point of this test is not "does it find an interface" -- it is that the
# three states stay *distinguishable*. The bug this whole refactor exists to kill
# was not a wrong interface as such, it was a wrong interface that presented as
# healthy: units sat in "activating" forever and `systemctl --failed` reported
# the VM as clean. So the assertions below care as much about what does NOT
# happen (no spurious failure, no silent success) as about the happy path.
{ pkgs, ... }:
pkgs.testers.nixosTest {
  name = "uplink-resolver";

  nodes.machine =
    { lib, ... }:
    {
      imports = [ ../../modules/common/networking/uplink-resolver.nix ];

      # eth1 is the test network. Give it a default route so there is a real
      # uplink to find, and name a deliberately wrong expectedInterface so the
      # mismatch warning -- the entire payload of phase 1 -- is exercised.
      networking = {
        useDHCP = false;
        defaultGateway = {
          address = "192.168.1.1";
          interface = "eth1";
        };
      };

      ghaf.networking.uplinkResolver = {
        enable = true;
        internalInterface = "ethint0";
        expectedInterface = "wlp0s5f0";
      };

      # Keep the option's type happy without pulling NetworkManager into the
      # test closure; the dispatcher itself is not what is under test here.
      networking.networkmanager.enable = lib.mkForce false;
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("ghaf-uplink-resolver.service")

    with subtest("resolved: publishes the default-route interface"):
        state = machine.succeed("cat /run/ghaf-uplink-state")
        assert "uplink_iface=eth1" in state, state
        assert "uplink_state=resolved" in state, state
        # The readiness flag is what dependent units gate on with
        # ConditionPathExists, so its presence is part of the contract.
        machine.succeed("test -e /run/ghaf-uplink-ready")

    with subtest("resolved: warns that the baked externalNic disagrees"):
        journal = machine.succeed("journalctl -u ghaf-uplink-resolver --no-pager")
        assert "WARNING" in journal, journal
        assert "wlp0s5f0" in journal and "eth1" in journal, journal

    with subtest("no uplink: reports it without failing"):
        machine.succeed("ip route del default")
        machine.systemctl("restart ghaf-uplink-resolver.service")
        state = machine.succeed("cat /run/ghaf-uplink-state")
        assert "uplink_state=none" in state, state
        assert "no default route" in state, state
        # Absent flag => dependents will show as skipped, not failed.
        machine.fail("test -e /run/ghaf-uplink-ready")
        # The resolver itself must NOT fail. "The dock is unplugged" is a
        # legitimate state; turning it into a failed unit trains people to
        # ignore failed units, which is how the original bug survived.
        machine.succeed("systemctl is-active ghaf-uplink-resolver.service")
        assert machine.succeed("systemctl --failed --no-legend").strip() == ""

    with subtest("no uplink: says so out loud"):
        journal = machine.succeed("journalctl -u ghaf-uplink-resolver --no-pager")
        assert "no uplink" in journal, journal

    with subtest("recovers when the uplink comes back"):
        machine.succeed("ip route add default via 192.168.1.1 dev eth1")
        machine.systemctl("restart ghaf-uplink-resolver.service")
        state = machine.succeed("cat /run/ghaf-uplink-state")
        assert "uplink_iface=eth1" in state, state
        assert "uplink_state=resolved" in state, state
        machine.succeed("test -e /run/ghaf-uplink-ready")

    with subtest("never claims the guest-facing interface as the uplink"):
        # If ethint0 somehow held the default route, routing multicast onto it
        # would bridge it straight back inwards. Rename eth1 to prove the
        # internal-interface guard fires on name, not on address.
        machine.succeed("ip route del default")
        machine.succeed("ip link set eth1 down")
        machine.succeed("ip link set eth1 name ethint0")
        machine.succeed("ip link set ethint0 up")
        machine.succeed("ip route add default via 192.168.1.1 dev ethint0")
        machine.systemctl("restart ghaf-uplink-resolver.service")
        state = machine.succeed("cat /run/ghaf-uplink-state")
        assert "uplink_state=none" in state, state
        assert "internal interface" in state, state
        machine.fail("test -e /run/ghaf-uplink-ready")
  '';
}
