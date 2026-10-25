# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Tests ghaf.firewall.allowedTCPPorts and allowedUDPPorts: an input entry with
# `from` admits only those sources and refuses the rest, a plain port stays open
# to everyone, and output entries are the only way out besides other Ghaf hosts.
{ pkgs, lib, ... }:
let
  ports = {
    open = 8001;
    byName = 8002;
    udpByName = 8003;
    openedElsewhere = 8004;
    merged = 8005;
    perInterface = 8006;
    inRange = 8007;
    extraInput = 8009;
    outAnywhere = 9101;
    outTo = 9102;
    outUndeclared = 9103;
    outTwoTo = 9104;
    outRangeFirst = 9105;
    outRangeLast = 9106;
    udpOut = 9201;
    udpUndeclared = 9202;
  };

  # firewall.nix reads these from givc and hosts.nix; declaring just what it
  # touches keeps the test to the module under test.
  stubs =
    { lib, ... }:
    {
      options.ghaf = {
        networking.hosts = lib.mkOption { type = lib.types.attrsOf lib.types.attrs; };
        givc.policyClient = {
          enable = lib.mkEnableOption "givc policy client (stub for tests)";
          policies = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
        };
      };
    };

  tcpListeners =
    tcpPorts:
    pkgs.writeText "listeners.py" ''
      import socket
      import threading


      def tcp(port):
          s = socket.socket()
          s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
          s.bind(("0.0.0.0", port))
          s.listen()
          while True:
              s.accept()[0].close()


      def udp(port):
          s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
          s.bind(("0.0.0.0", port))
          while True:
              data, peer = s.recvfrom(64)
              s.sendto(data, peer)


      for port in [${lib.concatMapStringsSep ", " toString tcpPorts}]:
          threading.Thread(target=tcp, args=(port,)).start()
      udp(${toString ports.udpByName})
    '';

  listenerService = tcpPorts: {
    wantedBy = [ "multi-user.target" ];
    serviceConfig.ExecStart = "${lib.getExe pkgs.python3} ${tcpListeners tcpPorts}";
  };

  # The assertion messages a configuration with these TCP entries fails with, or
  # null when evaluating its rules throws.
  failures =
    entries:
    let
      system = pkgs.nixos {
        imports = [
          ../../modules/common/firewall
          stubs
        ];
        ghaf = {
          networking.hosts.known.ipv4 = "192.168.1.10";
          firewall = {
            enable = true;
            allowedTCPPorts = entries;
          };
        };
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "none";
          fsType = "tmpfs";
        };
        system.stateVersion = lib.trivial.release;
      };
      rendered = builtins.tryEval (builtins.deepSeq system.config.networking.firewall.extraCommands true);
    in
    if rendered.success then
      map (a: a.message) (lib.filter (a: !a.assertion) system.config.assertions)
    else
      null;

  rejected =
    name: entries: message:
    let
      found = failures entries;
    in
    lib.assertMsg (
      if message == null then found == null else found != null && lib.any (lib.hasInfix message) found
    ) "firewall-source-ports: ${name} was not rejected";

  # Misconfigurations must stop the build; checked while evaluating this test.
  misconfigurations = [
    (lib.assertMsg (
      failures [
        22
        {
          port = 443;
          direction = "output";
        }
        {
          port = 124;
          from = [ "known" ];
        }
      ] == [ ]
    ) "firewall-source-ports: a valid configuration was rejected")
    (rejected "a port both open and limited" [
      124
      {
        port = 124;
        from = [ "known" ];
      }
    ] "listed both open to everyone and limited")
    (rejected "an input entry with `to`" [
      {
        port = 124;
        to = [ "known" ];
      }
    ] "an input entry needs a single `port`")
    (rejected "an output entry with `from`" [
      {
        port = 443;
        direction = "output";
        from = [ "known" ];
      }
    ] "an input entry needs a single `port`")
    (rejected "an input entry without a port" [
      { from = [ "known" ]; }
    ] "an input entry needs a single `port`")
    (rejected "an input entry with a port range" [
      {
        port = {
          from = 124;
          to = 125;
        };
        from = [ "known" ];
      }
    ] "an input entry needs a single `port`")
    (rejected "a port range that ends before it starts" [
      {
        port = {
          from = 8810;
          to = 8801;
        };
        direction = "output";
      }
    ] "must not end before it starts")
    (rejected "an empty `from`" [
      {
        port = 124;
        from = [ ];
      }
    ] "would match nothing")
    (rejected "an empty `to`" [
      {
        port = 443;
        direction = "output";
        to = [ ];
      }
    ] "would match nothing")
    (rejected "an unknown host name" [
      {
        port = 124;
        from = [ "nonexistent-vm" ];
      }
    ] null)
  ];

  client = {
    environment.systemPackages = [ pkgs.python3 ];
    networking.firewall.enable = false;
    systemd.services.listeners = listenerService (
      with ports;
      [
        outAnywhere
        outTo
        outUndeclared
        outTwoTo
        outRangeFirst
        outRangeLast
      ]
    );
  };
in
assert lib.all lib.id misconfigurations;
pkgs.testers.nixosTest {
  name = "firewall-source-ports";

  nodes.server =
    { nodes, ... }:
    let
      allowed = nodes.allowed.networking.primaryIPAddress;
      denied = nodes.denied.networking.primaryIPAddress;
    in
    {
      imports = [
        ../../modules/common/firewall
        stubs
        # Two services limiting the same port, each to its own client.
        {
          ghaf.firewall.allowedTCPPorts = [
            {
              port = ports.merged;
              from = [ "allowed" ];
            }
          ];
        }
        {
          ghaf.firewall.allowedTCPPorts = [
            {
              port = ports.merged;
              from = [ denied ];
            }
          ];
        }
      ];

      # The stock kernel already has every module the firewall asks for; applying
      # the patches would only rebuild it.
      boot.kernelPatches = lib.mkForce [ ];

      ghaf = {
        networking.hosts.allowed.ipv4 = allowed;
        firewall = {
          enable = true;
          logRefusedOutput = true;
          allowedTCPPorts = [
            ports.open
            {
              port = ports.byName;
              from = [ "allowed" ];
            }
            {
              port = ports.openedElsewhere;
              from = [ allowed ];
            }
            {
              port = ports.perInterface;
              from = [ "allowed" ];
            }
            {
              port = ports.inRange;
              from = [ "allowed" ];
            }
            {
              port = ports.extraInput;
              from = [ "allowed" ];
            }
            {
              port = ports.outAnywhere;
              direction = "output";
            }
            {
              port = ports.outTo;
              direction = "output";
              to = [ "192.0.2.1" ];
            }
            {
              port = ports.outTwoTo;
              direction = "output";
              to = [ "192.0.2.1" ];
            }
            {
              port = ports.outTwoTo;
              direction = "output";
              to = [ denied ];
            }
            {
              port = {
                from = ports.outRangeFirst;
                to = ports.outRangeLast;
              };
              direction = "output";
            }
          ];
          allowedUDPPorts = [
            {
              port = ports.udpByName;
              from = [ "allowed" ];
            }
            {
              port = ports.udpOut;
              direction = "output";
            }
          ];
          extra.input.filter = [
            "-p tcp --dport ${toString ports.extraInput} -j ghaf-fw-conncheck-accept"
          ];
        };
      };

      environment.systemPackages = [ pkgs.python3 ];

      # As other modules would: opened without going through ghaf.firewall.
      networking.firewall = {
        allowedTCPPorts = [ ports.openedElsewhere ];
        interfaces.eth1.allowedTCPPorts = [ ports.perInterface ];
        allowedTCPPortRanges = [
          {
            from = ports.inRange;
            to = ports.inRange + 1;
          }
        ];
      };

      systemd.services.listeners = listenerService (
        with ports;
        [
          open
          byName
          openedElsewhere
          merged
          perInterface
          inRange
          extraInput
        ]
      );
    };

  nodes.allowed = client;
  nodes.denied = client;

  testScript =
    { nodes, ... }:
    ''
      def tcp(port, host="server"):
          return f"python3 -c 'import socket; socket.create_connection((\"{host}\", {port}), timeout=3)'"

      # Refused by the receiving firewall, as a closed port would be.
      def refused(port):
          return f"({tcp(port)} 2>&1 || true) | grep ConnectionRefusedError"

      # OUTPUT drops the SYN silently, so TCP retries until the connect times out.
      def dropped(port, host):
          return f"({tcp(port, host)} 2>&1 || true) | grep 'timed out'"

      # Sends a datagram and waits for the echo.
      def udp(port):
          return (
              "python3 -c 'import socket; s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); "
              f"s.settimeout(3); s.sendto(b\"x\", (\"server\", {port})); s.recvfrom(64)'"
          )

      # Only sends: the result is whether the local firewall let the datagram out.
      def udp_send(host, port):
          return (
              "python3 -c 'import socket; s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); "
              "s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(\"${nodes.server.networking.primaryIPAddress}\")); "
              f"s.sendto(b\"x\", (\"{host}\", {port}))'"
          )

      start_all()
      server.wait_for_unit("firewall.service")
      server.wait_for_unit("listeners.service")
      server.wait_for_open_port(${toString ports.open})
      for client in [allowed, denied]:
          client.wait_for_unit("listeners.service")
          client.wait_for_open_port(${toString ports.outTwoTo})

      with subtest("a plain port is open to everyone"):
          allowed.succeed(tcp(${toString ports.open}))
          denied.succeed(tcp(${toString ports.open}))

      with subtest("a port limited by host name"):
          allowed.succeed(tcp(${toString ports.byName}))
          denied.succeed(refused(${toString ports.byName}))
          server.succeed("journalctl -k | grep 'refused connection: .*DPT=${toString ports.byName}'")

      with subtest("a port another module opened, limited by address"):
          allowed.succeed(tcp(${toString ports.openedElsewhere}))
          denied.succeed(refused(${toString ports.openedElsewhere}))

      with subtest("a port opened on one interface, limited"):
          allowed.succeed(tcp(${toString ports.perInterface}))
          denied.succeed(refused(${toString ports.perInterface}))

      with subtest("a port opened through a range, limited"):
          allowed.succeed(tcp(${toString ports.inRange}))
          denied.succeed(refused(${toString ports.inRange}))

      with subtest("a port opened by an extra input rule, limited"):
          allowed.succeed(tcp(${toString ports.extraInput}))
          denied.succeed(refused(${toString ports.extraInput}))

      with subtest("two services limiting one port admit both their sources"):
          allowed.succeed(tcp(${toString ports.merged}))
          denied.succeed(tcp(${toString ports.merged}))
          rules = server.succeed("iptables -S ghaf-fw-restrict-tcp-${toString ports.merged}")
          assert rules.count("-j ACCEPT") == 2, rules

      with subtest("a limited UDP port"):
          allowed.succeed(udp(${toString ports.udpByName}))
          denied.succeed(f"({udp(${toString ports.udpByName})} 2>&1 || true) | grep 'timed out'")

      with subtest("an output entry without `to` reaches any destination"):
          server.succeed(tcp(${toString ports.outAnywhere}, "denied"))

      with subtest("an output entry with `to` reaches only those destinations"):
          server.succeed(dropped(${toString ports.outTo}, "denied"))

      with subtest("two output entries for one port allow both destinations"):
          server.succeed(tcp(${toString ports.outTwoTo}, "denied"))

      with subtest("an output port range reaches every port in it"):
          server.succeed(tcp(${toString ports.outRangeFirst}, "denied"))
          server.succeed(tcp(${toString ports.outRangeLast}, "denied"))

      with subtest("an undeclared outgoing port is dropped and logged"):
          server.succeed(dropped(${toString ports.outUndeclared}, "denied"))
          server.succeed("journalctl -k | grep 'refused output: .*DPT=${toString ports.outUndeclared}'")

      with subtest("UDP output follows the same entries"):
          server.succeed(udp_send("denied", ${toString ports.udpOut}))
          server.succeed(f"({udp_send('denied', ${toString ports.udpUndeclared})} 2>&1 || true) | grep 'Operation not permitted'")

      with subtest("ICMP leaves to any destination"):
          server.succeed("ping -4 -c 1 -W 3 denied")

      with subtest("multicast, loopback and other Ghaf hosts stay reachable"):
          server.succeed(udp_send("239.255.255.250", 1900))
          server.succeed(tcp(${toString ports.byName}, "127.0.0.1"))
          server.succeed(tcp(${toString ports.outUndeclared}, "allowed"))

      with subtest("a reload keeps the limits"):
          server.succeed("systemctl restart firewall.service")
          allowed.succeed(tcp(${toString ports.byName}))
          denied.succeed(refused(${toString ports.byName}))
          denied.succeed(tcp(${toString ports.open}))
          server.succeed(dropped(${toString ports.outUndeclared}, "denied"))
          server.succeed(tcp(${toString ports.outAnywhere}, "denied"))
    '';
}
