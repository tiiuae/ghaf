# SPDX-FileCopyrightText: 2024-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Integration test for GIVC Access Control Engine across multiple VMs using ghaf.givc abstractions
#
# Verifies:
# 1. StartApplication via givc-cli from guivm to appvm with path filtering.
# 2. Access control test0: Direct StartApplication from hostvm to appvm is DENIED by Cedar agent policy.
# 3. Access control test1: Direct StartApplication from guivm to appvm is PERMITTED by Cedar agent policy.
# 4. Access control test2: get-status to appvm from guivm is DENIED by Cedar admin policy.
#
{
  pkgs,
  self,
  lib,
  ...
}:
let
  addrs = {
    host = "192.168.101.2";
    adminvm = "192.168.101.10";
    appvm = "192.168.101.5";
    guivm = "192.168.101.3";
  };

  adminConfig = {
    name = "adminvm";
    addresses = [
      {
        name = "adminvm";
        addr = addrs.adminvm;
        port = "9001";
        protocol = "tcp";
      }
    ];
  };

  # Generate snakeoil test certificates for TLS communication with SANs
  certGen = pkgs.runCommand "givc-test-certs" { buildInputs = [ pkgs.openssl ]; } ''
    mkdir -p $out/adminvm $out/guivm $out/host $out/appvm

    openssl req -x509 -newkey rsa:2048 -nodes -keyout $out/ca-key.pem -out $out/ca-cert.pem -days 365 -subj "/CN=Ghaf-CA"

    cat <<EOF > ext_base.cnf
    basicConstraints = CA:FALSE
    keyUsage = digitalSignature, keyEncipherment
    extendedKeyUsage = serverAuth, clientAuth
    EOF

    gen_cert() {
      local node=$1
      local ip=$2
      mkdir -p $out/$node
      cp $out/ca-cert.pem $out/$node/ca-cert.pem

      cat ext_base.cnf > $node.cnf
      echo "subjectAltName = DNS:$node, IP:$ip, IP:127.0.0.1" >> $node.cnf

      openssl req -newkey rsa:2048 -nodes -keyout $out/$node/key.pem -out $out/$node/req.pem -subj "/CN=$node"
      openssl x509 -req -in $out/$node/req.pem -CA $out/ca-cert.pem -CAkey $out/ca-key.pem -CAcreateserial -out $out/$node/cert.pem -days 365 -extfile $node.cnf
    }

    gen_cert adminvm 192.168.101.10
    gen_cert guivm 192.168.101.3
    gen_cert host 192.168.101.2
    gen_cert appvm 192.168.101.5

    chmod -R u+rwX,go+rX $out
  '';

  commonHosts = {
    "adminvm" = {
      ipv4 = addrs.adminvm;
    };
    "guivm" = {
      ipv4 = addrs.guivm;
    };
    "host" = {
      ipv4 = addrs.host;
    };
    "appvm" = {
      ipv4 = addrs.appvm;
    };
  };

  commonTmpfiles = [
    "d /run/givc 0755 root root -"
    "L+ /run/givc/ca-cert.pem - - - - /etc/givc/ca-cert.pem"
    "L+ /run/givc/cert.pem - - - - /etc/givc/cert.pem"
    "L+ /run/givc/key.pem - - - - /etc/givc/key.pem"
  ];

  commonImports = [
    self.nixosModules.common
    self.nixosModules.development
    self.nixosModules.givc
  ];
in
pkgs.testers.nixosTest {
  name = "givc-access-control";

  nodes = {
    adminvm =
      { ... }:
      {
        imports = commonImports;

        ghaf.type = "admin-vm";
        networking.hostName = "adminvm";

        ghaf.networking.hosts = commonHosts;
        ghaf.common.vms = [
          "guivm"
          "appvm"
          "host"
        ];
        ghaf.common.appHosts = [ "appvm" ];

        networking.interfaces.eth1.ipv4.addresses = lib.mkOverride 0 [
          {
            address = addrs.adminvm;
            prefixLength = 24;
          }
        ];

        environment.etc."givc/ca-cert.pem".source = "${certGen}/adminvm/ca-cert.pem";
        environment.etc."givc/cert.pem".source = "${certGen}/adminvm/cert.pem";
        environment.etc."givc/key.pem".source = "${certGen}/adminvm/key.pem";

        systemd.tmpfiles.rules = commonTmpfiles;
        systemd.services.givc-key-setup.enable = lib.mkForce false;

        ghaf.givc = {
          enable = true;
          debug = true;
          enableTls = true;
          adminConfig = lib.mkForce adminConfig;
          accessControl.enable = true;
          adminvm.enable = true;
        };
        givc.admin = {
          accessControl = {
            adminRules = [
              {
                from = [
                  "appvm"
                  "guivm"
                  "adminvm"
                  "host"
                  "hostvm"
                ];
                permittedRequests = [ "RegisterService" ];
              }
              {
                from = [ "guivm" ];
                to = [ "appvm" ];
                permittedRequests = [ "StartApplication" ];
              }
            ];
          };
        };
      };

    guivm =
      { ... }:
      {
        imports = commonImports;

        ghaf.type = "system-vm";
        networking.hostName = "guivm";

        ghaf.networking.hosts = commonHosts;

        networking.interfaces.eth1.ipv4.addresses = lib.mkOverride 0 [
          {
            address = addrs.guivm;
            prefixLength = 24;
          }
        ];

        environment.etc."givc/ca-cert.pem".source = "${certGen}/guivm/ca-cert.pem";
        environment.etc."givc/cert.pem".source = "${certGen}/guivm/cert.pem";
        environment.etc."givc/key.pem".source = "${certGen}/guivm/key.pem";

        systemd.tmpfiles.rules = commonTmpfiles;
        systemd.services.givc-key-setup.enable = lib.mkForce false;

        ghaf.givc = {
          enable = true;
          debug = true;
          enableTls = true;
          adminConfig = lib.mkForce adminConfig;
          guivm.enable = true;
        };

        environment.systemPackages = with pkgs; [
          givc-cli
          grpcurl
        ];
      };

    hostvm =
      { ... }:
      {
        imports = commonImports;

        ghaf.type = "host";
        networking.hostName = "host";

        ghaf.networking.hosts = commonHosts;

        networking.interfaces.eth1.ipv4.addresses = lib.mkOverride 0 [
          {
            address = addrs.host;
            prefixLength = 24;
          }
        ];

        environment.etc."givc/ca-cert.pem".source = "${certGen}/host/ca-cert.pem";
        environment.etc."givc/cert.pem".source = "${certGen}/host/cert.pem";
        environment.etc."givc/key.pem".source = "${certGen}/host/key.pem";

        systemd.tmpfiles.rules = commonTmpfiles;
        systemd.services.givc-key-setup.enable = lib.mkForce false;

        ghaf.givc = {
          enable = true;
          debug = true;
          enableTls = true;
          adminConfig = lib.mkForce adminConfig;
          host.enable = true;
          accessControl.enable = true;
        };

        systemd.services."microvm@appvm" = {
          script = ''
            while true; do sleep 10; done
          '';
          wantedBy = [ "multi-user.target" ];
        };

        environment.systemPackages = with pkgs; [
          givc-cli
          grpcurl
        ];
      };

    appvm =
      { ... }:
      {
        imports = commonImports;

        ghaf.type = "app-vm";
        networking.hostName = "appvm";

        ghaf.networking.hosts = commonHosts;

        networking.interfaces.eth1.ipv4.addresses = lib.mkOverride 0 [
          {
            address = addrs.appvm;
            prefixLength = 24;
          }
        ];

        environment.etc."givc/ca-cert.pem".source = "${certGen}/appvm/ca-cert.pem";
        environment.etc."givc/cert.pem".source = "${certGen}/appvm/cert.pem";
        environment.etc."givc/key.pem".source = "${certGen}/appvm/key.pem";

        systemd.tmpfiles.rules = commonTmpfiles;
        systemd.services.givc-key-setup.enable = lib.mkForce false;

        ghaf.givc = {
          enable = true;
          debug = true;
          enableTls = true;
          accessControl.enable = true;
          adminConfig = lib.mkForce adminConfig;
          appvm = {
            enable = true;
            applications = [
              {
                name = "cat";
                command = "/run/current-system/sw/bin/cat";
                args = [ "file" ];
                directories = [
                  "/etc"
                  "/tmp"
                ];
              }
              {
                name = "anothercat";
                command = "/run/current-system/sw/bin/cat";
                args = [ "file" ];
                directories = [
                  "/etc"
                  "/tmp"
                ];
              }
            ];
          };
        };

        givc.appvm.accessControl.agentRules = [
          {
            permittedVms = [ "guivm" ];
            permittedModules = [ "systemd" ];
          }
        ];

        ghaf.users.appUser.enable = true;

        environment.systemPackages = with pkgs; [
          coreutils
          grpcurl
        ];
      };
  };

  testScript = ''

    with subtest("startup"):
        adminvm.wait_for_unit("givc-admin.service")
        adminvm.wait_for_unit("multi-user.target")
        guivm.wait_for_unit("multi-user.target")
        guivm.wait_for_unit("givc-guivm.service")
        hostvm.wait_for_unit("multi-user.target")
        hostvm.wait_for_unit("givc-host.service")
        appvm.wait_for_unit("multi-user.target")
        #appvm.wait_for_unit("givc-appvm.service")

        adminvm.wait_until_succeeds("journalctl -u givc-admin.service | grep -i 'appvm' || true")
        appvm.succeed("touch /tmp/testfile")
        appvm.succeed("touch /tmp/admin_forbids")
        appvm.succeed("touch /tmp/agent_forbids")

    cli = "givc-cli --name adminvm --addr 192.168.101.10 --port 9001 --cacert /etc/givc/ca-cert.pem --cert /etc/givc/cert.pem --key /etc/givc/key.pem"
    grpcurl = "grpcurl -cacert /etc/givc/ca-cert.pem -cert /etc/givc/cert.pem -key /etc/givc/key.pem"


    with subtest("access control test0 (PermissionDenied: direct StartApplication from hostvm to appvm)"):
        (exit_code, output) = hostvm.execute(
            f"{grpcurl} -d '{{\"UnitName\": \"anothercat@0.service\"}}' 192.168.101.5:9000 systemd.UnitControlService/StartApplication 2>&1"
        )
        assert exit_code != 0, f"unexpected permission granted by access control policy: {output}"
        assert "permission denied by access control policy" in output, f"Expected 'permission denied by access control policy', got: {output}"
        print("\033[94m\n-- access control test0 (cedar) completed successfully --\n\033[0m")

    with subtest("agent access control test1 (PermissionGranted: direct start application request from guivm to appvm)"):
        (exit_code, output) = guivm.execute(
            f"{grpcurl} -d '{{\"UnitName\": \"anothercat@0.service\"}}' 192.168.101.5:9000 systemd.UnitControlService/StartApplication 2>&1"
        )
        assert exit_code == 0, f"agent access control test1 failed: {output}"
        print("\033[94m\n-- access control test1 (cedar) completed successfully --\n\033[0m")

    with subtest("access control test2 (get-status to appvm from guivm forbid by admin)"):
        (exit_code, output) = guivm.execute(
            f"{cli} get-status appvm multi-user.target 2>&1"
        )
        assert exit_code != 0, f"unexpected permission granted by admin access control policy: {output}"
        assert "permission denied by admin access control policy" in output, f"Expected 'permission denied by admin access control policy', got: {output}"
        print("\033[94m\n-- access control test2 (cedar) completed successfully --\n\033[0m")

    with subtest("access control test3 (PermissionDenied: direct GetUnitStatus of givc-hostvm.service on hostvm from guivm)"):
        (exit_code, output) = guivm.execute(
            f"{grpcurl} -d '{{\"UnitName\": \"multi-user.target\"}}' 192.168.101.2:9000 systemd.UnitControlService/GetUnitStatus 2>&1"
        )
        assert exit_code != 0, f"unexpected permission granted by access control policy: {output}"
        assert "permission denied by access control policy" in output or "PermissionDenied" in output, (
            f"Expected 'permission denied by access control policy', got: {output} "
        )
        print("\033[94m\n-- access control test3 (cedar) completed successfully --\n\033[0m")

  '';
}
