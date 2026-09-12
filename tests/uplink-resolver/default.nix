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

  # Declares its own only interface to be the guest-facing one, so the resolver
  # must refuse it even though it holds the default route.
  nodes.internalonly =
    { lib, ... }:
    {
      imports = [ ../../modules/common/networking/uplink-resolver.nix ];
      networking = {
        useDHCP = false;
        defaultGateway = {
          address = "192.168.1.1";
          interface = "eth1";
        };
        networkmanager.enable = lib.mkForce false;
      };
      ghaf.networking.uplinkResolver = {
        enable = true;
        internalInterface = "eth1";
      };
    };

  # Pins the uplink to an interface that is not the one carrying the default
  # route, to prove the pin is obeyed and the disagreement is reported.
  nodes.pinned =
    { lib, ... }:
    {
      imports = [ ../../modules/common/networking/uplink-resolver.nix ];
      networking = {
        useDHCP = false;
        defaultGateway = {
          address = "192.168.1.1";
          interface = "eth1";
        };
        networkmanager.enable = lib.mkForce false;
      };
      ghaf.networking.uplinkResolver = {
        enable = true;
        forceInterface = "lo";
      };
    };

  nodes.machine =
    { lib, ... }:
    {
      imports = [
        ../../modules/common/networking/uplink-resolver.nix
        ../../modules/common/firewall
        # firewall.nix reaches into ghaf.givc.policyClient; declaring the two
        # options it touches keeps this test from depending on the givc and
        # storagevm stacks. Same reasoning as tests/firewall.
        (
          { lib, ... }:
          {
            options.ghaf.givc.policyClient = {
              enable = lib.mkEnableOption "givc policy client (stub for tests)";
              policies = lib.mkOption {
                type = lib.types.attrsOf lib.types.anything;
                default = { };
              };
            };
          }
        )
      ];

      # Exercise the uplink firewall chains: a rule naming @UPLINK@ must reach
      # iptables with the resolved interface substituted, and must be withdrawn
      # when the uplink goes away rather than left pointing at a stale one.
      ghaf.firewall = {
        enable = true;
        uplink = {
          enable = true;
          rules.forward.filter = [
            "-i @UPLINK@ -o ethint0 -p tcp --sport 8008 -j ACCEPT"
          ];
        };
      };

      # eth1 is the test network, with a default route so there is a real uplink
      # to find.
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
        forceInterface = "";
        dependentUnits = [
          "uplink-consumer.service"
          "uplink-reconcile-stand-in.service"
          "ghaf-firewall-uplink.service"
        ];
      };

      # Stand-in for smcroute / nw-packet-forwarder. The real ones need a
      # patched kernel (IP_MROUTE) and the whole chromecast stack, which would
      # make this test enormous for no extra signal: what has to be proven is
      # the *mechanism* -- gate on the flag, read the interface from the state
      # file, get restarted when it changes -- and that is identical here.
      systemd.services.uplink-consumer = {
        description = "Stand-in consumer of the resolved uplink";
        wantedBy = [ "multi-user.target" ];
        after = [ "ghaf-uplink-resolver.service" ];
        unitConfig.ConditionPathExists = "/run/ghaf-uplink-ready";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          # shellcheck disable=SC1091
          . /run/ghaf-uplink-state
          echo "consumer: using $uplink_ifaces"
          echo "$uplink_ifaces" >/run/uplink-consumer-saw
        '';
      };

      # Stand-in for nw-packet-forwarder-reconcile specifically: the one real
      # consumer *not* gated on the ready flag, since it has to run even with
      # no uplink at all, to tear down anything left over from one that just
      # disappeared. That makes it the one consumer that actually sources the
      # state file while uplink_reason is set to a multi-word value -- gating
      # on the flag like uplink-consumer above never exercises that.
      systemd.services.uplink-reconcile-stand-in = {
        description = "Stand-in for the one consumer not gated on the ready flag";
        wantedBy = [ "multi-user.target" ];
        after = [ "ghaf-uplink-resolver.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          # shellcheck disable=SC1091
          . /run/ghaf-uplink-state
          echo "reconcile-stand-in: state=$uplink_state reason=$uplink_reason ifaces=$uplink_ifaces"
        '';
      };

      # Keep the option's type happy without pulling NetworkManager into the
      # test closure; the dispatcher itself is not what is under test here.
      networking.networkmanager.enable = lib.mkForce false;
    };

  testScript = ''
    machine.start()  # internalonly is started later, in its own subtest
    machine.wait_for_unit("ghaf-uplink-resolver.service")

    with subtest("resolved: publishes the default-route interface"):
        state = machine.succeed("cat /run/ghaf-uplink-state")
        assert 'uplink_ifaces="eth1"' in state, state
        assert "uplink_state=resolved" in state, state
        # The readiness flag is what dependent units gate on with
        # ConditionPathExists, so its presence is part of the contract.
        machine.succeed("test -e /run/ghaf-uplink-ready")

    with subtest("multiple uplinks: publishes every default-route interface"):
        # A device can carry more than one default route at once (Wi-Fi and a
        # docked Ethernet both up); a dummy netdev with its own default route
        # stands in for the second one without needing a second test vlan.
        machine.succeed("ip link add dummy0 type dummy")
        machine.succeed("ip link set dummy0 up")
        machine.succeed("ip addr add 192.168.2.2/24 dev dummy0")
        machine.succeed("ip route add default via 192.168.2.1 dev dummy0 metric 9999")
        machine.systemctl("restart ghaf-uplink-resolver.service")
        state = machine.succeed("cat /run/ghaf-uplink-state")
        assert "uplink_state=resolved" in state, state
        ifaces_line = next(l for l in state.splitlines() if l.startswith("uplink_ifaces="))
        ifaces = ifaces_line.split("=", 1)[1].strip('"').split()
        assert set(ifaces) == {"eth1", "dummy0"}, ifaces_line

        machine.succeed("ip route del default dev dummy0")
        machine.succeed("ip link del dummy0")
        machine.systemctl("restart ghaf-uplink-resolver.service")
        state = machine.succeed("cat /run/ghaf-uplink-state")
        assert 'uplink_ifaces="eth1"' in state, state

    with subtest("a pin is honoured, but not silently"):
        # An explicit forceInterface wins -- a setting that some consumers obeyed
        # and others ignored would be its own silent-wrongness bug -- but if it
        # disagrees with where traffic actually goes, that has to be said.
        pinned.start()
        pinned.wait_for_unit("ghaf-uplink-resolver.service")
        state = pinned.succeed("cat /run/ghaf-uplink-state")
        assert 'uplink_ifaces="lo"' in state, state
        assert "uplink_state=resolved" in state, state
        journal = pinned.succeed("journalctl -u ghaf-uplink-resolver --no-pager")
        assert "WARNING" in journal, journal
        assert "pinned to 'lo'" in journal and "eth1" in journal, journal

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

    with subtest("dependent not gated on the ready flag survives a multi-word reason"):
        # nw-packet-forwarder-reconcile is the one consumer that has to run
        # even with no uplink, to tear down anything left over -- this is
        # what actually sources uplink_reason while it holds a multi-word
        # value like "no default route", unlike the ready-flag-gated
        # stand-in above, which never reads the file in this state.
        # Unquoted, that value would make `. stateFile` try to run "default"
        # as a command and abort under set -e before doing anything.
        machine.wait_until_succeeds(
            "systemctl is-active uplink-reconcile-stand-in.service", timeout=30
        )
        journal = machine.succeed("journalctl -u uplink-reconcile-stand-in --no-pager")
        assert "reason=no default route" in journal, journal
        assert machine.succeed("systemctl --failed --no-legend").strip() == ""

    with subtest("recovers when the uplink comes back"):
        machine.succeed("ip route add default via 192.168.1.1 dev eth1")
        machine.systemctl("restart ghaf-uplink-resolver.service")
        state = machine.succeed("cat /run/ghaf-uplink-state")
        assert 'uplink_ifaces="eth1"' in state, state
        assert "uplink_state=resolved" in state, state
        machine.succeed("test -e /run/ghaf-uplink-ready")

    with subtest("dependent consumes the resolved uplink"):
        machine.wait_for_unit("uplink-consumer.service")
        assert machine.succeed("cat /run/uplink-consumer-saw").strip() == "eth1"

    with subtest("dependent is SKIPPED, not failed, when the uplink goes away"):
        machine.succeed("rm -f /run/uplink-consumer-saw")
        machine.succeed("ip route del default")
        machine.systemctl("restart ghaf-uplink-resolver.service")
        # The resolver restarts dependents via ExecStartPost --no-block, so give
        # systemd a moment to settle before judging the outcome.
        machine.wait_until_succeeds(
            "test \"$(systemctl is-active uplink-consumer.service)\" != active", timeout=30
        )
        # The distinction this whole design exists for: not running, and not
        # failed either. A failed unit here would be wrong (the dock being out
        # is legitimate) and would train people to ignore failed units.
        assert "failed" not in machine.succeed("systemctl is-active uplink-consumer.service || true")
        assert machine.succeed("systemctl --failed --no-legend").strip() == ""
        # And it must not have run and silently done nothing.
        machine.fail("test -e /run/uplink-consumer-saw")
        # The reason is visible rather than having to be inferred.
        status = machine.succeed("systemctl status uplink-consumer.service || true")
        assert "ondition" in status, status

    with subtest("dependent comes back by itself when the uplink returns"):
        machine.succeed("ip route add default via 192.168.1.1 dev eth1")
        machine.systemctl("restart ghaf-uplink-resolver.service")
        machine.wait_until_succeeds("test -e /run/uplink-consumer-saw", timeout=30)
        assert machine.succeed("cat /run/uplink-consumer-saw").strip() == "eth1"

    with subtest("firewall rules are applied with the resolved interface"):
        machine.wait_for_unit("ghaf-firewall-uplink.service")
        rules = machine.succeed("iptables -t filter -S ghaf-fw-uplink-fwd-filter")
        # The placeholder must be gone and the real interface in its place.
        assert "@UPLINK@" not in rules, rules
        assert "-i eth1" in rules and "--sport 8008" in rules, rules
        # And the chain must actually be reachable from the ghaf forward chain,
        # not just populated in isolation.
        parent = machine.succeed("iptables -t filter -S ghaf-fw-fwd-filter")
        assert "ghaf-fw-uplink-fwd-filter" in parent, parent

    with subtest("firewall rules are withdrawn when the uplink goes away"):
        machine.succeed("ip route del default")
        machine.systemctl("restart ghaf-uplink-resolver.service")
        machine.wait_until_succeeds(
            "test \"$(systemctl is-active ghaf-firewall-uplink.service)\" != active", timeout=30
        )
        # Empty chain, not stale rules naming an interface that is gone.
        rules = machine.succeed("iptables -t filter -S ghaf-fw-uplink-fwd-filter")
        assert "--sport 8008" not in rules, rules
        assert machine.succeed("systemctl --failed --no-legend").strip() == ""
        # Restore for the remaining subtests.
        machine.succeed("ip route add default via 192.168.1.1 dev eth1")
        machine.systemctl("restart ghaf-uplink-resolver.service")

    with subtest("never claims the guest-facing interface as the uplink"):
        # Asserted on a separate node that simply declares eth1 as its internal
        # interface, rather than by moving the default route onto ethint0 on
        # this one. Route surgery does not hold: networkd owns eth1 and restores
        # its default route, so the guard ends up racing the network stack
        # instead of being tested.
        internalonly.start()
        internalonly.wait_for_unit("ghaf-uplink-resolver.service")
        state = internalonly.succeed("cat /run/ghaf-uplink-state")
        assert "uplink_state=none" in state, state
        assert "internal interface" in state, state
        internalonly.fail("test -e /run/ghaf-uplink-ready")
  '';
}
