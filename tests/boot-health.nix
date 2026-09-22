# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs }:
pkgs.testers.nixosTest {
  name = "boot-health-before-login";
  nodes.machine = { lib, ... }: {
    imports = [ ../modules/partitioning/boot-health.nix ];
    options.microvm.vms = lib.mkOption {
      type = lib.types.attrs;
      default.net-vm = { };
    };
    config = {
      ghaf.boot-health = {
        enable = true;
        requiredVmNames = [ "net-vm" ];
      };
      systemd.services."microvm@net-vm".serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.coreutils}/bin/true";
        RemainAfterExit = true;
      };
      systemd.services.wait-for-login.serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
      };
      systemd.targets.system-login = {
        wantedBy = [ "microvms.target" ];
        requires = [ "wait-for-login.service" ];
        after = [ "wait-for-login.service" ];
      };
      systemd.targets.microvms = {
        wantedBy = [ "multi-user.target" ];
        wants = [ "microvm@net-vm.service" ];
      };
    };
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("microvm@net-vm.service")
    # Exercise the real health script: missing storage must fail before login.
    machine.wait_until_succeeds("journalctl -b -u ghaf-boot-health --no-pager | grep -F '/boot is not a mounted writable ESP'", timeout=30)
    machine.succeed("test $(systemctl show wait-for-login -p ActiveState --value) = activating")
    machine.succeed("test $(systemctl show ghaf-boot-health -p ExecMainStatus --value) = 1")
    machine.fail("test -e /persist/common/ota/accepted-generation")
  '';
}
