# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Tests ghaf.common.egress: a NAT gateway forwards a new connection from a
# host behind it only when that host's output entries allow it, whatever the
# host's own firewall says.
{ pkgs, lib, ... }:
let
  ports = {
    anywhere = 9101;
    elsewhere = 9102;
    undeclared = 9103;
    toOutside = 9104;
    rangeFirst = 9105;
    rangeLast = 9106;
    udp = 9201;
    udpUndeclared = 9202;
  };

  # firewall.nix reads these from givc and hosts.nix; declaring just what it
  # touches keeps the test to the module under test.
  stubs =
    { lib, ... }:
    {
      options.ghaf = {
        networking.hosts = lib.mkOption { type = lib.types.attrsOf lib.types.attrs; };
        common.egress = lib.mkOption { type = lib.types.attrsOf lib.types.attrs; };
        givc.policyClient = {
          enable = lib.mkEnableOption "givc policy client (stub for tests)";
          policies = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
        };
      };
    };

  listeners = pkgs.writeText "listeners.py" ''
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


    for port in [${
      lib.concatMapStringsSep ", " toString (
        with ports;
        [
          anywhere
          elsewhere
          undeclared
          toOutside
          rangeFirst
          rangeLast
        ]
      )
    }]:
        threading.Thread(target=tcp, args=(port,)).start()
    threading.Thread(target=udp, args=(${toString ports.udpUndeclared},)).start()
    udp(${toString ports.udp})
  '';

  # As common.nix collects them: merged entries, every field present.
  output =
    entry:
    {
      port = null;
      direction = "output";
      from = null;
      to = null;
    }
    // entry;

  # Its own firewall is off, so only the gateway can stop it.
  inside =
    { nodes, ... }:
    {
      environment.systemPackages = [ pkgs.python3 ];
      networking.firewall.enable = false;
      networking.defaultGateway = {
        inherit ((lib.head nodes.gateway.networking.interfaces.eth1.ipv4.addresses)) address;
        interface = "eth1";
      };
    };
in
pkgs.testers.nixosTest {
  name = "firewall-egress";

  nodes.gateway =
    { nodes, ... }:
    let
      outside = nodes.outside.networking.primaryIPAddress;
    in
    {
      imports = [
        ../../modules/common/firewall
        stubs
      ];

      # The stock kernel already has every module the firewall asks for; applying
      # the patches would only rebuild it.
      boot.kernelPatches = lib.mkForce [ ];

      virtualisation.vlans = [
        1
        2
      ];
      networking.nat = {
        enable = true;
        internalInterfaces = [ "eth1" ];
        externalInterface = "eth2";
      };

      ghaf = {
        networking.hosts = {
          inside.ipv4 = nodes.inside.networking.primaryIPAddress;
          stranger.ipv4 = nodes.stranger.networking.primaryIPAddress;
        };
        firewall = {
          enable = true;
          logRefusedOutput = true;
        };
        common.egress = {
          inside = {
            tcp = map output [
              { port = ports.anywhere; }
              {
                port = ports.elsewhere;
                to = [ "192.0.2.1" ];
              }
              {
                port = ports.toOutside;
                to = [ outside ];
              }
              {
                port = {
                  from = ports.rangeFirst;
                  to = ports.rangeLast;
                };
              }
            ];
            udp = map output [ { port = ports.udp; } ];
          };
          # No port: every UDP port, at outside only.
          stranger.udp = map output [ { to = [ outside ]; } ];
        };
      };
    };

  nodes.inside = inside;
  nodes.stranger = inside;

  nodes.outside = {
    virtualisation.vlans = [ 2 ];
    networking.firewall.enable = false;
    systemd.services.listeners = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = "${lib.getExe pkgs.python3} ${listeners}";
    };
  };

  testScript =
    { nodes, ... }:
    ''
      outside_ip = "${nodes.outside.networking.primaryIPAddress}"

      def tcp(port):
          return f"python3 -c 'import socket; socket.create_connection((\"{outside_ip}\", {port}), timeout=3)'"

      # Sends a datagram and waits for the echo.
      def udp(port):
          return (
              "python3 -c 'import socket; s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); "
              f"s.settimeout(3); s.connect((\"{outside_ip}\", {port})); s.send(b\"x\"); s.recv(64)'"
          )

      # The gateway answers with icmp-admin-prohibited, which the sender sees as
      # EHOSTUNREACH rather than a timeout.
      def rejected(command):
          return f"({command} 2>&1 || true) | grep 'No route to host'"

      start_all()
      gateway.wait_for_unit("firewall.service")
      outside.wait_for_unit("listeners.service")
      outside.wait_for_open_port(${toString ports.anywhere})
      for node in [inside, stranger]:
          node.wait_for_unit("multi-user.target")

      def check():
          with subtest("an entry without `to` reaches any destination"):
              inside.succeed(tcp(${toString ports.anywhere}))

          with subtest("an entry with `to` reaches only those destinations"):
              inside.succeed(rejected(tcp(${toString ports.elsewhere})))
              inside.succeed(tcp(${toString ports.toOutside}))

          with subtest("a port range reaches every port in it"):
              inside.succeed(tcp(${toString ports.rangeFirst}))
              inside.succeed(tcp(${toString ports.rangeLast}))

          with subtest("an undeclared port is rejected and logged"):
              inside.succeed(rejected(tcp(${toString ports.undeclared})))
              gateway.succeed("journalctl -k | grep 'refused forward: .*DPT=${toString ports.undeclared}'")

          with subtest("UDP follows the same entries"):
              inside.succeed(udp(${toString ports.udp}))
              inside.succeed(rejected(udp(${toString ports.udpUndeclared})))

          with subtest("entries apply only to their own host"):
              stranger.succeed(rejected(tcp(${toString ports.anywhere})))

          with subtest("an entry without a port reaches every port of its destination"):
              stranger.succeed(udp(${toString ports.udp}))
              stranger.succeed(udp(${toString ports.udpUndeclared}))

      check()
      members = gateway.succeed("${pkgs.ipset}/bin/ipset list ghaf-fw-egress")
      assert "udp:${toString ports.udp}" in members, members

      with subtest("a reload keeps the limits"):
          gateway.succeed("systemctl restart firewall.service")
          check()
    '';
}
