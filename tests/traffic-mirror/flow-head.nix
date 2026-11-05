# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Tests the flow-head classifiers of the traffic mirror: only the head of each
# flow the host opened reaches the mirror, sized per port, and Suricata reading
# the mirror still detects what lies in that head.
{ pkgs, ... }:
let
  flowBytes = 65536;
  flowHeadObjs = pkgs.callPackage ../../modules/microvm/common/mirror-flow-head {
    inherit flowBytes;
  };

  sids = {
    dns = 1000001;
    sni = 1000002;
    uri = 1000003;
    early = 1000004;
    late = 1000005;
  };

  rules = pkgs.writeText "local.rules" ''
    alert dns any any -> any any (msg:"dns"; dns.query; content:"ids-test.example"; nocase; sid:${toString sids.dns};)
    alert tls any any -> any any (msg:"sni"; tls.sni; content:"ids-test.example"; sid:${toString sids.sni};)
    alert http any any -> any any (msg:"uri"; http.uri; content:"/ids-test"; sid:${toString sids.uri};)
    alert tcp any any -> any any (msg:"early"; flow:established,to_client; content:"IDS-MARKER-EARLY"; sid:${toString sids.early};)
    alert tcp any any -> any any (msg:"late"; flow:established,to_client; content:"IDS-MARKER-LATE"; sid:${toString sids.late};)
  '';

  # Markers inside and well past the 1 MiB HTTP limit, in 5 MiB files.
  webRoot = pkgs.runCommand "ids-test-root" { } ''
    mkdir $out
    echo ok > $out/ids-test
    { head -c 524288 /dev/zero; printf IDS-MARKER-EARLY; head -c 4194304 /dev/zero; } > $out/early.bin
    { head -c 3145728 /dev/zero; printf IDS-MARKER-LATE; head -c 2097152 /dev/zero; } > $out/late.bin
  '';

  cert = pkgs.runCommand "ids-test-cert" { nativeBuildInputs = [ pkgs.openssl ]; } ''
    mkdir $out
    openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=ids-test.example \
      -keyout $out/key.pem -out $out/cert.pem
  '';
in
pkgs.testers.nixosTest {
  name = "traffic-mirror-flow-head";

  nodes.server = {
    virtualisation.vlans = [ 1 ];
    networking.firewall.allowedTCPPorts = [
      80
      443
      8888
    ];
    environment.systemPackages = [ pkgs.netcat-openbsd ];
    services.nginx = {
      enable = true;
      virtualHosts."ids-test.example" = {
        default = true;
        root = webRoot;
        addSSL = true;
        sslCertificate = "${cert}/cert.pem";
        sslCertificateKey = "${cert}/key.pem";
        # 8888 is in no flowLimits entry, so it gets flowBytes.
        listen = [
          {
            addr = "0.0.0.0";
            port = 80;
          }
          {
            addr = "0.0.0.0";
            port = 443;
            ssl = true;
          }
          {
            addr = "0.0.0.0";
            port = 8888;
          }
        ];
      };
    };
  };

  # Plays net-vm: mirrors its uplink to a local `mirror` device, which Suricata
  # reads in place of ids-vm.
  nodes.gateway = {
    virtualisation = {
      vlans = [ 1 ];
      memorySize = 2048;
      cores = 2;
    };
    boot.kernelModules = [ "dummy" ];
    system.extraDependencies = [ flowHeadObjs ];
    environment.systemPackages = [
      pkgs.curl
      pkgs.dig
    ];
    systemd.services.suricata.serviceConfig = {
      ExecStart = builtins.concatStringsSep " " [
        "${pkgs.suricata}/bin/suricata"
        "-c ${pkgs.suricata}/etc/suricata/suricata.yaml"
        "-S ${rules}"
        "--af-packet=mirror"
        "-k none"
        "--set stream.checksum-validation=no"
        # Deeper than any limit, so a missing alert is the mirror's doing.
        "--set stream.reassembly.depth=8mb"
        "--set app-layer.protocols.tls.ja3-fingerprints=yes"
        "--set app-layer.protocols.tls.ja4-fingerprints=yes"
      ];
      LogsDirectory = "suricata";
      RuntimeDirectory = "suricata";
    };
  };

  testScript =
    { nodes, ... }:
    ''
      server_ip = "${nodes.server.networking.primaryIPAddress}"
      gateway_ip = "${nodes.gateway.networking.primaryIPAddress}"
      eve = "/var/log/suricata/eve.json"
      https = f"--resolve ids-test.example:443:{server_ip} https://ids-test.example"

      def mirror_with(match):
          for hook in ["ingress", "egress"]:
              gateway.succeed(f"tc filter del dev eth1 {hook} || true")
              gateway.succeed(
                  f"tc filter add dev eth1 {hook} protocol all pref 10 {match(hook)} "
                  "action mirred egress mirror dev mirror"
              )

      def mirrored():
          return int(gateway.succeed("cat /sys/class/net/mirror/statistics/tx_bytes"))

      # Rate-limited: at full speed Suricata's capture ring overflows on the
      # uncapped mirror, and the dropped packets take the markers with them.
      def fetch(url):
          before = mirrored()
          gateway.succeed(f"curl -sfk --limit-rate 2M -o /dev/null {url}")
          sent = mirrored() - before
          print(f"mirrored {sent} bytes of {url}")
          return sent

      def alerts(sid):
          return int(gateway.succeed(f"grep -c '\"signature_id\":{sid},' {eve} || true"))

      def wait_alert(sid, count=1):
          try:
              gateway.wait_until_succeeds(f"[ $(grep -c '\"signature_id\":{sid},' {eve}) -ge {count} ]", timeout=60)
          except Exception:
              print(gateway.execute("tail -n 100 /var/log/suricata/stats.log | grep -E 'capture|gap'")[1])
              raise

      start_all()
      server.wait_for_open_port(80)
      server.wait_for_open_port(443)
      server.wait_for_open_port(8888)
      gateway.wait_for_unit("multi-user.target")
      gateway.succeed("ip link add mirror type dummy && ip link set mirror up")
      gateway.succeed("tc qdisc add dev eth1 clsact")
      gateway.succeed("systemctl start suricata")
      gateway.wait_until_succeeds("grep -qi 'engine started' /var/log/suricata/suricata.log", timeout=120)

      with subtest("without the classifier the whole flow is mirrored and inspected"):
          mirror_with(lambda hook: "matchall")
          assert fetch(f"http://{server_ip}/late.bin") > 5 * 1048576
          wait_alert(${toString sids.late})

      late_before = alerts(${toString sids.late})
      mirror_with(lambda hook: f"bpf obj ${flowHeadObjs}/{hook}.o sec classifier")

      with subtest("plain HTTP is mirrored up to its byte limit"):
          assert 1048576 <= fetch(f"http://{server_ip}/late.bin") < 2 * 1048576

      with subtest("TLS is mirrored only through its handshake"):
          assert fetch(f"{https}/late.bin") < 256 * 1024

      with subtest("a port without a limit of its own gets flowBytes"):
          assert ${toString flowBytes} <= fetch(f"http://{server_ip}:8888/late.bin") < 256 * 1024

      with subtest("flows the host did not open are not mirrored"):
          before = mirrored()
          server.execute(f"for i in $(seq 20); do nc -z -w 1 {gateway_ip} 9; done")
          assert mirrored() - before < 500, f"mirrored {mirrored() - before} bytes"

      with subtest("what lies in the head is still detected"):
          fetch(f"http://{server_ip}/early.bin")
          wait_alert(${toString sids.early})
          fetch(f"http://{server_ip}/ids-test")
          wait_alert(${toString sids.uri})
          gateway.execute(f"dig +tries=1 +time=1 @{server_ip} ids-test.example")
          wait_alert(${toString sids.dns})
          fetch(f"{https}/ids-test")
          wait_alert(${toString sids.sni})
          gateway.wait_until_succeeds(f"grep '\"event_type\":\"tls\"' {eve} | grep -q '\"ja4\"'", timeout=60)

      with subtest("what lies past the head is not"):
          assert alerts(${toString sids.late}) == late_before, "late marker detected past the limit"
    '';
}
