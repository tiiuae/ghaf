# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs, ... }:
let
  gateway = pkgs.writeText "fortivpn-test-gateway.py" ''
    import http.server
    import ssl
    from pathlib import Path
    from urllib.parse import parse_qs

    class Handler(http.server.BaseHTTPRequestHandler):
        def reply(self, body, cookie=False):
            self.send_response(200)
            if cookie:
                self.send_header("Set-Cookie", "SVPNCOOKIE=fixture; Path=/")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if "SVPNCOOKIE=fixture" in self.headers.get("Cookie", ""):
                Path("/run/fortivpn-tunnel-contact").touch()
                if Path("/run/fortivpn-hold-tunnel").exists():
                    self.connection.recv(1)
                    return
                self.send_error(503)
            else:
                self.reply(b"<html>Login</html>")

        def do_POST(self):
            form = parse_qs(self.rfile.read(int(self.headers["Content-Length"])).decode())
            if form.get("credential") == ["fixture-password"]:
                self.reply(b"ret=1,tokeninfo=otp,reqid=1,polid=1,grp=1,portal=test,peer=test,magic=abc")
            elif form.get("code") == ["123456"]:
                self.reply(b"ok", cookie=True)
            else:
                self.send_error(403)

    server = http.server.HTTPServer(("127.0.0.1", 8443), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain("certificate.pem", "key.pem")
    server.socket = context.wrap_socket(server.socket, server_side=True)
    server.serve_forever()
  '';
in
pkgs.testers.nixosTest {
  name = "fortivpn";

  nodes.machine =
    { lib, ... }:
    {
      imports = [
        ../modules/common/services/fortivpn.nix
        ../modules/common/users/auxiliary.nix
      ];

      options = {
        ghaf = {
          givc.enable = lib.mkEnableOption "GIVC";
          givc.guivm.dbusProxies = lib.mkOption {
            type = lib.types.attrs;
            default = { };
          };
          networking.hosts = lib.mkOption { type = lib.types.attrs; };
          services.wifi.enable = lib.mkEnableOption "Wi-Fi";
          storagevm.enable = lib.mkEnableOption "storage VM";
          storagevm.directories = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
          security.audit.extraRules = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
        };
        givc.dbusproxy.system.policy.talk = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
      };

      config = {
        networking.hostName = "net-vm";
        networking.networkmanager.logLevel = "INFO";
        networking.networkmanager.unmanaged = [ "eth0" ];
        networking.networkmanager.dispatcherScripts = [
          {
            type = "pre-up";
            source = pkgs.writeShellScript "test-early-dhcp" ''
              [[ "$1" == vpn-test0 && -s /run/ghaf-fortivpn-resume ]] || exit 0
              # A DHCP notification can arrive before NetworkManager activates the uplink.
              for hook in /etc/NetworkManager/dispatcher.d/03userscript????; do
                "$hook" "$1" dhcp4-change || exit 1
              done
              if [[ -s /run/ghaf-fortivpn-resume ]]; then
                touch /run/fortivpn-dhcp-deferred
              fi
            '';
          }
        ];
        systemd.services.NetworkManager-dispatcher.serviceConfig = import ../modules/common/systemd/hardened-configs/NetworkManager-dispatcher.nix;
        powerManagement.powerDownCommands = "systemctl stop NetworkManager";
        powerManagement.resumeCommands = "systemctl start NetworkManager";
        ghaf = {
          services.fortivpn.enable = true;
          givc.enable = true;
          networking.hosts.net-vm.interfaceName = "eth1";
          users.proxyUser = {
            enable = true;
            extraGroups = [ "networkmanager" ];
          };
        };
        users.users.outsider.isNormalUser = true;
        environment.systemPackages = [ pkgs.openssl ];
        systemd.services.test-gateway = {
          wantedBy = [ "multi-user.target" ];
          preStart = ''
            ${lib.getExe pkgs.openssl} req -x509 -newkey rsa:2048 -nodes \
              -keyout key.pem -out certificate.pem -days 1 -subj /CN=localhost
          '';
          serviceConfig = {
            StateDirectory = "fortivpn-test-gateway";
            WorkingDirectory = "/var/lib/fortivpn-test-gateway";
            ExecStart = "${lib.getExe pkgs.python3} ${gateway}";
          };
        };
      };
    };

  testScript = ''
    import shlex
    from xml.etree import ElementTree

    machine.start(allow_reboot=True)
    machine.wait_for_unit("ghaf-fortivpn.service")
    machine.wait_for_open_port(8443)
    public = "busctl call org.ghaf.FortiVpn /org/ghaf/FortiVpn org.ghaf.FortiVpn1 "
    private = (
        "busctl call org.ghaf.FortiVpn.Authentication /org/ghaf/FortiVpnAuthentication "
        "org.ghaf.FortiVpn.Authentication1 "
    )
    proxy = "runuser -u proxyuser -- "
    outsider = "runuser -u outsider -- "

    with subtest("public API and private authentication boundaries"):
        xml = machine.succeed(proxy + "busctl --xml-interface introspect org.ghaf.FortiVpn /org/ghaf/FortiVpn")
        method = ElementTree.fromstring(xml).find(".//method[@name='PendingAuthentication']")
        assert method is not None
        assert [a.get("type") for a in method.findall("arg[@direction='out']")] == ["s", "s", "s", "b"]
        machine.succeed(proxy + public + 'PendingAuthentication s ""')
        machine.fail(outsider + public + 'PendingAuthentication s ""')
        machine.fail(proxy + private + "Authenticate 'a{sa{sv}}' 0")
        machine.fail(proxy + private + 'Cancel s fixture')
        for name in ("org.ghaf.FortiVpn", "org.ghaf.FortiVpn.Authentication"):
            machine.fail(
                outsider + "busctl call org.freedesktop.DBus /org/freedesktop/DBus "
                "org.freedesktop.DBus RequestName su " + name + " 4"
            )

    def create_profile(name, bundle=()):
        output = machine.succeed(
            proxy + public + "CreateProfile ssqssssaysayaysay "
            + name + ' localhost 8443 "" fixture-user fixture-password '
            + fingerprint + " " + " ".join([str(len(bundle)), *bundle]) + ' "" 0 0 "" 0'
        )
        return shlex.split(output)[1]

    with subtest("persistent OpenConnect profile and private credentials"):
        fingerprint = machine.succeed(
            "openssl x509 -in /var/lib/fortivpn-test-gateway/certificate.pem "
            "-outform DER | sha256sum"
        ).split()[0]
        uuid = create_profile("integration")
        credentials = "/var/lib/ghaf/fortivpn/" + uuid + "/auth.json"
        machine.succeed("test $(stat -c %a:%U " + credentials + ") = 600:root")
        machine.fail(proxy + "cat " + credentials)
        machine.fail(outsider + "cat " + credentials)
        data = machine.succeed("nmcli -g vpn.service-type,vpn.data connection show uuid " + uuid)
        assert "org.freedesktop.NetworkManager.openconnect" in data
        assert "protocol = fortinet" in data
        machine.succeed(
            "nmcli connection add type dummy ifname vpn-test0 con-name test-uplink "
            "connection.autoconnect no ipv4.method manual ipv4.addresses 192.0.2.1/24 "
            "ipv4.gateway 192.0.2.254 ipv6.method disabled"
        )
        machine.succeed("nmcli connection up test-uplink")

    def pending():
        return shlex.split(machine.succeed(proxy + public + 'PendingAuthentication s ""'))[1]

    def start():
        machine.succeed(proxy + "nmcli --wait 0 connection up uuid " + uuid + " ifname vpn-test0")
        machine.wait_until_succeeds(proxy + public + 'PendingAuthentication s "" | grep -q ":1"')
        return pending()

    with subtest("plugin gets an MFA cookie and presents it to the test gateway"):
        machine.succeed("busctl monitor --match=type=signal,interface=org.ghaf.FortiVpn1,member=AuthenticationPending > /run/prompt-signal 2>&1 &")
        request = start()
        machine.wait_until_succeeds("grep -q Member=AuthenticationPending /run/prompt-signal")
        machine.succeed(proxy + public + "AnswerAuthentication ssb " + request + " 123456 false")
        machine.wait_until_succeeds("test -e /run/fortivpn-tunnel-contact")
        assert not pending()

    with subtest("cancelling a second prompt after a NetworkManager restart"):
        machine.succeed("systemctl restart NetworkManager")
        machine.wait_for_unit("NetworkManager.service")
        machine.succeed("nmcli connection up test-uplink")
        request = start()
        machine.succeed(proxy + public + 'AnswerAuthentication ssb ' + request + ' "" true')
        machine.wait_until_succeeds("! nmcli -t -f UUID connection show --active | grep -Fx " + uuid)
        assert not pending()

    def finish_test_tunnel(request):
        machine.succeed("rm -f /run/fortivpn-tunnel-contact")
        machine.succeed(proxy + public + "AnswerAuthentication ssb " + request + " 123456 false")
        machine.wait_until_succeeds("test -e /run/fortivpn-tunnel-contact")
        # Supply the tunnel configuration normally negotiated by PPP to the real VPN plugin.
        plugin, = machine.succeed(
            "busctl --acquired --no-legend | awk '/^org[.]freedesktop[.]NetworkManager[.]openconnect/ {print $1}'"
        ).split()
        machine.succeed(
            "VPNGATEWAY=192.0.2.254 TUNDEV=fixture-tun INTERNAL_IP4_ADDRESS=198.51.100.1 "
            "INTERNAL_IP4_NETMASK=255.255.255.255 NM_DBUS_SERVICE_OPENCONNECT=" + plugin
            + " ${pkgs.ghaf-networkmanager-openconnect}/libexec/nm-openconnect-service-openconnect-helper"
        )
        machine.wait_until_succeeds("nmcli -g GENERAL.STATE con show uuid " + uuid + " | grep -Fx activated")

    with subtest("wake waits for an uplink and reconnects a saved VPN once"):
        machine.succeed("touch /run/fortivpn-hold-tunnel && ip tuntap add dev fixture-tun mode tun")
        finish_test_tunnel(start())
        machine.succeed(
            "systemd-run --unit=test-sleep --property=Wants=sleep.target "
            "--property=After=sleep.target /run/current-system/sw/bin/sleep infinity"
        )
        machine.wait_until_fails("systemctl is-active --quiet NetworkManager")
        resume = "/run/ghaf-fortivpn-resume"
        machine.succeed("grep -Fx " + uuid + " " + resume + ".sleep")
        machine.succeed("ip link del vpn-test0")
        machine.succeed("systemctl stop test-sleep")
        machine.wait_for_unit("NetworkManager.service")
        machine.succeed("test -s " + resume)
        machine.succeed("nmcli connection up test-uplink")
        machine.succeed("test -e /run/fortivpn-dhcp-deferred")
        machine.wait_until_succeeds(proxy + public + 'PendingAuthentication s "" | grep -q ":1"')
        machine.fail("test -e " + resume)
        finish_test_tunnel(pending())
        machine.succeed("nmcli connection down uuid " + uuid)
        machine.wait_until_succeeds("! nmcli -t -f UUID connection show --active | grep -Fx " + uuid)
        machine.succeed("nmcli connection down test-uplink && nmcli connection up test-uplink")
        assert not pending()

    with subtest("saved profile survives reboot"):
        machine.reboot()
        machine.wait_for_unit("ghaf-fortivpn.service")
        machine.succeed("nmcli connection show uuid " + uuid)
        machine.succeed("test -f " + credentials)
        machine.fail(proxy + "cat " + credentials)

    with subtest("deleting a profile removes its password and imported private key"):
        bundle = machine.succeed(
            "cd /var/lib/fortivpn-test-gateway && openssl pkcs12 -export "
            "-in certificate.pem -inkey key.pem -passout pass: | od -An -v -tu1"
        ).split()
        deleted = create_profile("delete-online", bundle)
        directory = "/var/lib/ghaf/fortivpn/" + deleted
        machine.succeed("test -f " + directory + "/auth.json && test -f " + directory + "/client-key.pem")
        machine.succeed("systemctl restart NetworkManager && nmcli connection delete uuid " + deleted)
        machine.wait_until_succeeds("test ! -e " + directory, timeout=30)
        machine.succeed("test -f " + credentials)

    with subtest("startup cleans profiles deleted while the backend was stopped"):
        deleted = create_profile("delete-offline")
        directory = "/var/lib/ghaf/fortivpn/" + deleted
        machine.succeed("systemctl stop ghaf-fortivpn && nmcli connection delete uuid " + deleted)
        machine.succeed("test -f " + directory + "/auth.json")
        machine.succeed("systemctl start ghaf-fortivpn")
        machine.wait_until_succeeds("test ! -e " + directory, timeout=30)
        machine.succeed("test -f " + credentials)

    with subtest("cleanup preserves saved credentials while NetworkManager is unavailable"):
        machine.succeed("systemctl stop ghaf-fortivpn NetworkManager")
        mask = "/run/systemd/system.control/NetworkManager.service"
        machine.succeed("mkdir -p /run/systemd/system.control && ln -s /dev/null " + mask + " && systemctl daemon-reload")
        machine.succeed("test $(systemctl show -P LoadState NetworkManager) = masked")
        machine.succeed("systemctl start ghaf-fortivpn")
        machine.wait_until_succeeds(
            "journalctl _SYSTEMD_INVOCATION_ID=$(systemctl show -P InvocationID ghaf-fortivpn) "
            "--grep='profile cleanup deferred'", timeout=60
        )
        machine.succeed("test -f " + credentials)
        machine.succeed("rm " + mask + " && systemctl daemon-reload && systemctl start NetworkManager")
        machine.succeed("nmcli connection delete uuid " + uuid)
        machine.wait_until_succeeds("test ! -e " + credentials, timeout=30)
  '';
}
