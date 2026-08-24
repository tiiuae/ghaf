# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  ...
}:
let
  certs = pkgs.runCommand "logseald-test-certificates" { nativeBuildInputs = [ pkgs.openssl ]; } ''
    mkdir -p "$out/admin" "$out/producer"
    openssl req -x509 -newkey rsa:2048 -nodes \
      -keyout ca-key.pem -out "$out/ca-cert.pem" -days 30 \
      -subj "/CN=logseald-test-ca"

    make_certificate() {
      name="$1"
      usage="$2"
      openssl req -newkey rsa:2048 -nodes \
        -keyout "$out/$name/key.pem" -out "$name.csr" -subj "/CN=$name"
      {
        echo "basicConstraints=CA:FALSE"
        echo "keyUsage=digitalSignature,keyEncipherment"
        echo "extendedKeyUsage=$usage"
        echo "subjectAltName=DNS:$name"
      } > "$name.ext"
      openssl x509 -req -in "$name.csr" -CA "$out/ca-cert.pem" \
        -CAkey ca-key.pem -CAcreateserial -out "$out/$name/cert.pem" \
        -days 30 -extfile "$name.ext"
      cp "$out/ca-cert.pem" "$out/$name/ca-cert.pem"
    }

    make_certificate admin "serverAuth,clientAuth"
    make_certificate producer "clientAuth"
  '';

  ghafOptionStubs =
    { lib, ... }:
    {
      options.ghaf = {
        type = lib.mkOption {
          type = lib.types.str;
          default = "system-vm";
        };

        givc = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          enableTls = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          host.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
        };

        security.audit = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          extraRules = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
        };
      };
    };

  commonNode = certificateName: {
    imports = [
      ../../modules/common/logging
      ../../modules/common/storage-persistence.nix
      ghafOptionStubs
    ];
    ghaf = {
      type = "system-vm";
      logging = {
        enable = true;
        fss.enable = false;
        recovery.enable = false;
        listener.address = "admin";
        logseald = {
          endpoint = {
            address = "admin";
            serverName = "admin";
          };
          tls = {
            caFile = "${certs}/${certificateName}/ca-cert.pem";
            certFile = "${certs}/${certificateName}/cert.pem";
            keyFile = "${certs}/${certificateName}/key.pem";
            timePolicy = "static-cert";
          };
        };
      };
      storagevm.enable = false;
    };
    networking.firewall.enable = false;
    services.timesyncd.enable = lib.mkForce true;
    systemd.services.givc-key-setup.enable = lib.mkForce false;
    systemd.services.systemd-tmpfiles-setup.serviceConfig = import ../../modules/common/systemd/hardened-configs/systemd-tmpfiles-setup.nix;
    # Exercise recovery by replaying the otherwise boot-only setup unit.
    systemd.services.systemd-tmpfiles-setup.unitConfig = {
      RefuseManualStart = lib.mkForce false;
      RefuseManualStop = lib.mkForce false;
    };
  };
in
pkgs.testers.nixosTest {
  name = "logging-logseald";

  nodes = {
    admin =
      _:
      lib.recursiveUpdate (commonNode "admin") {
        networking.hostName = "admin";
        ghaf.logging.logseald.sealer.enable = true;
      };

    producer =
      _:
      lib.recursiveUpdate (commonNode "producer") {
        networking.hostName = "producer";
        ghaf.logging.logseald.producer = {
          enable = true;
          blockRecords = 16;
          blockIntervalSeconds = 1;
          retryIntervalSeconds = 1;
          maxPendingBlocks = 64;
          windowEntries = 4;
        };
      };
  };

  testScript = ''
    import shlex

    start_all()
    admin.wait_for_unit("logseald-sealer.service")
    producer.wait_for_unit("logseald-producer.service")
    producer.succeed("systemctl is-active logseald-journal-permissions.service")
    producer.succeed("systemctl show logseald-journal-permissions.service -p CapabilityBoundingSet --value | grep -qw cap_fsetid")
    producer.fail("systemctl show systemd-tmpfiles-setup.service -p CapabilityBoundingSet --value | grep -qw cap_fsetid")
    producer.succeed("test \"$(ps -o egid= -p $(systemctl show systemd-journald.service -p MainPID --value) | tr -d ' ')\" = 0")
    admin.wait_for_open_port(59631)
    admin.succeed("runuser -u logseald-producer -- test ! -r /var/lib/logseald/sealer/sealer.key")
    admin.succeed("test \"$(stat -c '%a %U:%G' /run/logseald-sealer)\" = '750 logseald-sealer:logseald-proxy'")
    admin.succeed("test \"$(stat -c '%a %U:%G' /run/logseald-sealer/sealer.sock)\" = '660 logseald-sealer:logseald-proxy'")
    admin.succeed("runuser -u logseald-proxy -- test -w /run/logseald-sealer/sealer.sock")
    admin.succeed("runuser -u logseald-proxy -- test ! -x /var/lib/logseald/sealer")
    admin.succeed("runuser -u logseald-proxy -- test ! -r /var/lib/logseald/sealer/sealer.key")

    producer.succeed("systemd-cat --identifier=logseald-test echo ONLINE_MARKER")
    producer.wait_until_succeeds("test -n \"$(find /var/lib/logseald/producer/sealed -name '*.json' -print -quit)\"")
    producer.succeed("logseald verify-producer --state-dir /var/lib/logseald/producer --cert ${certs}/producer/cert.pem --source producer")
    admin.succeed("logseald verify-sealer --state-dir /var/lib/logseald/sealer")
    admin.succeed("test -s /var/lib/logseald/sealer/checkpoint.json")
    admin.succeed("test -z \"$(find /var/lib/logseald/sealer/ledger -name '*.json' -print -quit)\"")

    producer.succeed("systemctl stop systemd-timesyncd.service")
    baseline = int(producer.succeed("date +%s").strip())
    producer.succeed("chmod 0755 /var/log/journal /var/log/journal/$(cat /etc/machine-id)")
    producer.succeed("chgrp root /var/log/journal /var/log/journal/$(cat /etc/machine-id)")
    producer.succeed("chgrp root /var/log/journal/$(cat /etc/machine-id)/system.journal")
    producer.succeed("systemctl restart systemd-tmpfiles-setup.service")
    producer.wait_until_succeeds("test \"$(stat -c '%a %U:%G' /var/log/journal/$(cat /etc/machine-id))\" = '2755 root:systemd-journal'")
    producer.wait_for_unit("logseald-producer.service")
    producer.succeed("test \"$(stat -c '%a %U:%G' /var/log/journal/$(cat /etc/machine-id)/system.journal)\" = '640 root:systemd-journal'")
    for offset in (1800, -1800, 7776000, -7776000, 0):
        producer.succeed(f"date --set=@{baseline + offset}")
        producer.succeed("journalctl --rotate")
        marker = f"ROTATION_CLOCK_MARKER_{offset}"
        producer.succeed(f"systemd-cat --identifier=logseald-test echo {marker}")
        producer.succeed("journalctl --sync")
        producer.succeed("test \"$(stat -c '%a %U:%G' /var/log/journal/$(cat /etc/machine-id)/system.journal)\" = '640 root:systemd-journal'")
        producer.succeed("runuser -u logseald-producer -g systemd-journal -- journalctl -b -n 5 --no-pager")
        marker_check = (
            "import base64,json,pathlib; "
            "files=pathlib.Path('/var/lib/logseald/producer/sealed').glob('*.json'); "
            f"assert any({marker.encode()!r} in base64.b64decode(json.loads(p.read_text())['request']['body']) for p in files)"
        )
        producer.wait_until_succeeds("${pkgs.python3}/bin/python3 -c " + shlex.quote(marker_check))
        producer.succeed("logseald verify-producer --state-dir /var/lib/logseald/producer --cert ${certs}/producer/cert.pem --source producer")
        admin.succeed("logseald verify-sealer --state-dir /var/lib/logseald/sealer")
    producer.succeed("systemctl start systemd-timesyncd.service")
    producer.wait_until_succeeds("test -s /var/lib/logseald/producer/boundary.json")
    producer.succeed("systemctl stop logseald-producer.service")
    producer.succeed("test $(find /var/lib/logseald/producer/sealed -name '*.json' | wc -l) -le 4")
    producer.succeed("logseald verify-producer --state-dir /var/lib/logseald/producer --cert ${certs}/producer/cert.pem --source producer")
    producer.succeed("systemctl start logseald-producer.service")

    admin.succeed("systemctl stop logseald-sealer.service")
    producer.succeed("systemd-cat --identifier=logseald-test echo OFFLINE_MARKER")
    producer.wait_until_succeeds("test -n \"$(find /var/lib/logseald/producer/queue -name '*.json' -print -quit)\"")
    producer.succeed("systemctl is-active systemd-journald.service")

    admin.succeed("systemctl start logseald-sealer.service")
    admin.wait_for_open_port(59631)
    admin.wait_until_succeeds("test \"$(stat -c '%a %U:%G' /run/logseald-sealer/sealer.sock)\" = '660 logseald-sealer:logseald-proxy'")
    admin.succeed("runuser -u logseald-proxy -- test ! -r /var/lib/logseald/sealer/sealer.key")
    producer.wait_until_succeeds("test -z \"$(find /var/lib/logseald/producer/queue -name '*.json' -print -quit)\"")
    producer.succeed("logseald verify-producer --state-dir /var/lib/logseald/producer --cert ${certs}/producer/cert.pem --source producer")
    admin.succeed("logseald verify-sealer --state-dir /var/lib/logseald/sealer")
  '';
}
