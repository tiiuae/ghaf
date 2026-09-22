# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs, ... }:
pkgs.testers.nixosTest {
  name = "logging-recovery";

  nodes.machine = {
    imports = [ ../../modules/common/logging/common.nix ];
    ghaf.logging = {
      enable = true;
      recovery = {
        intervalSeconds = 1;
        cooldownSeconds = 5;
      };
    };
    virtualisation.memorySize = 512;
    services.timesyncd.enable = false;
    services.journald.settings.Journal.Storage = "persistent";
    services.openssh.enable = true;
    services.fail2ban = {
      enable = true;
      jails.sshd.settings = {
        enabled = true;
        backend = "systemd";
      };
    };
    # Stand-ins isolate recovery orchestration from remote endpoints.
    systemd.services = builtins.listToAttrs (
      map
        (name: {
          inherit name;
          value = {
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${pkgs.coreutils}/bin/true";
            };
          };
        })
        [
          "alloy"
          "systemd-journal-upload"
        ]
    );
  };

  testScript = ''
    import time

    start_all()
    for unit in ["ghaf-clock-jump-watcher", "fail2ban", "alloy", "systemd-journal-upload"]:
        machine.wait_for_unit(f"{unit}.service")

    def invocation(unit):
        return machine.succeed(f"systemctl show {unit}.service -p InvocationID --value").strip()

    journal = invocation("systemd-journald")
    jail = invocation("fail2ban")
    watcher = invocation("ghaf-clock-jump-watcher")
    machine.succeed("grep -Fx 'Seal=no' /etc/systemd/journald.conf.d/99-ghaf-sealing.conf")

    with subtest("Late sealing policy overrides a stale runtime activation file"):
        machine.succeed("mkdir -p /run/systemd/journald.conf.d")
        machine.succeed("printf '[Journal]\\nSeal=yes\\n' > /run/systemd/journald.conf.d/90-old-activation.conf")
        machine.succeed("systemd-analyze cat-config systemd/journald.conf | grep '^Seal=' | tail -1 | grep -Fx 'Seal=no'")
        machine.succeed("rm /run/systemd/journald.conf.d/90-old-activation.conf")

    with subtest("Recovery restarts forwarders without restarting journal readers"):
        previous = {unit: invocation(unit) for unit in ["alloy", "systemd-journal-upload"]}
        machine.succeed("systemctl start ghaf-journal-alloy-recover.service")
        for unit, old in previous.items():
            assert invocation(unit) != old
        recovered = {unit: invocation(unit) for unit in previous}
        machine.succeed("systemctl start ghaf-journal-alloy-recover.service")
        assert recovered == {unit: invocation(unit) for unit in recovered}

    for offset in [120, -120]:
        with subtest(f"Watcher detects realtime jump {offset}"):
            time.sleep(6)
            old = invocation("alloy")
            machine.succeed(f"date --set=@$(($(date +%s) + {offset}))")
            machine.wait_until_succeeds(f"test $(systemctl show alloy.service -p InvocationID --value) != {old}")
            assert invocation("systemd-journald") == journal
            assert invocation("fail2ban") == jail
            assert invocation("ghaf-clock-jump-watcher") == watcher
            machine.succeed("fail2ban-client status sshd")
            machine.succeed("logger -t recovery-test clock-jump-complete")
            machine.succeed("journalctl --sync")
            machine.succeed("journalctl -b -t recovery-test --no-pager | grep -F clock-jump-complete")

    machine.fail("journalctl -b -u fail2ban.service --no-pager | grep -F NoneType")
  '';
}
