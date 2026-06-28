# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# NixOS VM Test for Forward Secure Sealing (FSS) Functionality
#
# This test verifies that FSS is properly configured and working. FSS provides
# tamper-evident logging using HMAC-SHA256 chains for systemd journal entries.
#
# To debug interactively, see:
# https://blog.thalheim.io/2023/01/08/how-to-execute-nixos-tests-interactively-for-debugging/
#
# Build and run:
#   nix build .#checks.x86_64-linux.logging-fss
#
# Interactive debugging:
#   nix build .#checks.x86_64-linux.logging-fss.driver
#   ./result/bin/nixos-test-driver
#   # Then in the Python REPL: machine.shell_interact()
#
{
  pkgs,
  lib,
  ...
}:
let
  fssSetupTest = import ./test_scripts/fss_setup.nix;
  fssVerificationTest = import ./test_scripts/fss_verification.nix;
in
pkgs.testers.nixosTest {
  name = "logging-fss";

  nodes.fss =
    { ... }:
    {
      imports = [
        # Only import the modules needed for FSS testing
        ../../modules/common/logging/common.nix
        ../../modules/common/logging/fss.nix
        ../../modules/common/storage-persistence.nix
      ];

      # Mock ghaf options (used by fss.nix for keyPath and audit)
      options.ghaf = {
        type = lib.mkOption {
          type = lib.types.str;
          default = "host";
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

      config = {
        # Enable FSS with short seal interval for testing
        ghaf.logging.enable = true;
        ghaf.logging.fss = {
          enable = true;
          sealInterval = "1min";
          verifyOnBoot = true;
          activation.syncWaitSeconds = 1;
        };
        ghaf.logging.recovery.clockReady = {
          stableSeconds = 1;
          maxWaitSeconds = 5;
        };

        networking.hostName = "test-host";

        environment.etc."fss-verify-classifier.sh".text =
          builtins.readFile ../../modules/common/logging/fss-verify-classifier.sh;

        # Create required directories
        systemd.tmpfiles.rules = [
          "d /persist/common/journal-fss 0755 root root - -"
          "d /persist/common/journal-fss/test-host 0700 root root - -"
        ];

        # Test utilities
        environment.systemPackages = with pkgs; [
          coreutils
          gnugrep
          util-linux
          (callPackage ./test_scripts/fss-test.nix { })
        ];
      };
    };

  nodes.fssOnly =
    { config, ... }:
    {
      imports = [
        ../../modules/common/logging/common.nix
        ../../modules/common/logging/fss.nix
        ../../modules/common/storage-persistence.nix
      ];

      options.ghaf = {
        type = lib.mkOption {
          type = lib.types.str;
          default = "host";
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

      config = {
        ghaf.logging.enable = false;
        ghaf.logging.fss = {
          enable = true;
          sealInterval = "1min";
          verifyOnBoot = false;
          activation = {
            enable = false;
            syncWaitSeconds = 1;
          };
        };
        ghaf.logging.recovery.clockReady = {
          stableSeconds = 1;
          maxWaitSeconds = 5;
        };
        ghaf.storagevm.enable = true;

        networking.hostName = "fss-only";

        environment.etc."storagevm-directories".text =
          lib.concatStringsSep "\n" config.ghaf.storagevm.directories;

        systemd.tmpfiles.rules = [
          "d /persist/common/journal-fss 0755 root root - -"
          "d /persist/common/journal-fss/fss-only 0700 root root - -"
        ];
      };
    };

  nodes.statelessVm =
    { ... }:
    {
      imports = [
        ../../modules/common/logging/common.nix
        ../../modules/common/logging/fss.nix
        ../../modules/common/storage-persistence.nix
      ];

      options.ghaf = {
        type = lib.mkOption {
          type = lib.types.str;
          default = "app-vm";
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

      config = {
        ghaf.logging.enable = true;
        ghaf.logging.fss.enable = lib.mkForce false;
        ghaf.storagevm.enable = lib.mkForce false;
        networking.hostName = "stateless-vm";
      };
    };

  testScript = _: ''
    machine = fss
    fss_only = fssOnly
    stateless_vm = statelessVm
    machine.start(allow_reboot=True)
    fss_only.start()
    stateless_vm.start()
    machine.wait_for_unit("multi-user.target")
    fss_only.wait_for_unit("multi-user.target")
    stateless_vm.wait_for_unit("multi-user.target")

    with subtest("FSS stays disabled for stateless VMs"):
        stateless_vm.succeed("test ! -e /etc/systemd/system/journal-fss-setup.service")
        stateless_vm.succeed("test ! -e /etc/systemd/system/journal-fss-verify.service")
        stateless_vm.succeed("test ! -e /etc/systemd/system/ghaf-clock-ready.service")
        stateless_vm.succeed("""
          bash -lc '
            set -euo pipefail
            ! systemctl show systemd-journal-flush.service --property=After --property=Requires --property=Wants |
              grep -F "ghaf-clock-ready.service"
          '
        """)

    with subtest("FSS-only configs still emit and require clock readiness"):
        fss_only.wait_for_unit("ghaf-clock-ready.service")
        fss_only.succeed("test -e /etc/systemd/system/ghaf-clock-ready.service")
        fss_only.succeed("""
          bash -lc '
            set -euo pipefail
            systemctl show journal-fss-setup.service --property=After --property=Requires --property=Wants |
              grep -F "ghaf-clock-ready.service"
            systemctl cat ghaf-clock-ready.service |
              grep -F "RequiresMountsFor=/var/lib/ghaf/clock-ready"
            grep -Fx "/var/lib/ghaf/clock-ready" /etc/storagevm-directories
          '
        """)

    with subtest("Static FSS preserves marker/key rotation skip"):
        fss_only.wait_until_succeeds("""
          bash -lc '
            systemctl is-active --quiet journal-fss-setup.service ||
            systemctl is-failed --quiet journal-fss-setup.service ||
            [ "$(systemctl show journal-fss-setup.service --property=ConditionResult --value)" = "no" ]
          '
        """)
        fss_only.succeed("""
          bash -lc '
            set -euo pipefail
            MID=$(cat /etc/machine-id)
            DIR="/var/log/journal/$MID"
            KEY="$DIR/fss"
            [ -f "$KEY" ] || KEY="/run/log/journal/$MID/fss"
            MARKER="$DIR/fss-rotated"
            BASE="$DIR/fss-baseline-boot"

            test -f "$KEY"
            test -f "$MARKER"
            systemd-analyze cat-config systemd/journald.conf |
              grep -E "^[[:space:]]*Seal[[:space:]]*=[[:space:]]*yes"
            test ! -e /run/systemd/journald.conf.d/90-ghaf-fss-activation.conf

            printf "previous-boot\n" > "$BASE"
            chmod 0644 "$BASE"
            touch -d "@1000000000" "$KEY"
            touch -d "@1000000010" "$MARKER"
            old_marker_mtime="$(stat -c %Y "$MARKER")"

            systemctl restart journal-fss-setup.service >/tmp/journal-fss-setup-static-skip.log 2>&1
            [ "$(stat -c %Y "$MARKER")" = "$old_marker_mtime" ]
            ! grep -F "Rotating journal to ensure clean FSS state" /tmp/journal-fss-setup-static-skip.log
          '
        """)

    ${fssSetupTest { }}

    with subtest("FSS activation survives a real reboot without system journal failures"):
        boot1 = machine.succeed("cat /proc/sys/kernel/random/boot_id").strip()
        machine.succeed("systemctl reset-failed journal-fss-verify.service >/dev/null 2>&1 || true")
        machine.succeed("systemctl start journal-fss-verify.service")
        machine.succeed("sync")
        machine.reboot()
        machine.wait_for_unit("multi-user.target")
        machine.wait_until_succeeds("""
          bash -lc '
            systemctl is-active --quiet journal-fss-setup.service ||
            systemctl is-failed --quiet journal-fss-setup.service
          '
        """)
        machine.succeed(f"""
          bash -lc '
            set -euo pipefail
            source /etc/fss-verify-classifier.sh
            BOOT1="{boot1}"
            BOOT2="$(cat /proc/sys/kernel/random/boot_id)"
            [ "$BOOT2" != "$BOOT1" ]

            MID=$(cat /etc/machine-id)
            DIR="/var/log/journal/$MID"
            VERIFY_KEY="$(tr -d "[:space:]" < /persist/common/journal-fss/test-host/verification-key)"
            activation_state="$(cut -f1 "$DIR/fss-activation-state")"
            activation_boot="$(cut -f2 "$DIR/fss-activation-state")"

            [ "$activation_state" = "active" ]
            [ "$activation_boot" = "$BOOT2" ]
            [ "$(tr -d "[:space:]" < "$DIR/fss-baseline-boot")" = "$BOOT2" ]
            test -f "$DIR/fss-rotated"

            rotations=$(journalctl -b -u journal-fss-setup.service --no-pager |
              grep -c "Rotating journal to ensure clean FSS state" || true)
            [ "$rotations" -eq 1 ]

            effective_seal=$(systemd-analyze cat-config systemd/journald.conf | awk -F= '"'"'
              /^[[:space:]]*[#;]/ {{ next }}
              /^[[:space:]]*Seal[[:space:]]*=/ {{
                value = $2
                sub(/^[[:space:]]*/, "", value)
                sub(/[[:space:]]*[#;].*$/, "", value)
                sub(/[[:space:]]*$/, "", value)
                seal = tolower(value)
              }}
              END {{ print seal }}
            '"'"')
            [ "$effective_seal" = yes ]

            VERIFY_EXIT=0
            VERIFY_OUTPUT=$(journalctl --verify --verify-key="$VERIFY_KEY" 2>&1) || VERIFY_EXIT=$?
            fss_classify_verify_output "$VERIFY_OUTPUT"
            if [ -n "$FSS_ACTIVE_SYSTEM_FAILURES" ]; then
              printf "%s\n" "$VERIFY_OUTPUT"
              exit 1
            fi
            fss_verify_policy_decision \
              "$(fss_read_recorded_pre_fss_archive "$DIR/fss-pre-fss-archive")" \
              "$(fss_filter_valid_receipts "$(fss_read_receipts "$DIR/fss-recovery-receipts")")" \
              "$(fss_filter_valid_receipts "$(fss_read_pre_activation_receipts "$DIR/fss-pre-activation-receipts")")" \
              "$BOOT2" \
              "$VERIFY_EXIT"
            if [ "$FSS_VERDICT" = "fail" ]; then
              printf "verdict=%s tags=%s reason=%s\n%s\n" \
                "$FSS_VERDICT" "$FSS_VERDICT_TAGS" "$FSS_VERDICT_REASON" "$VERIFY_OUTPUT"
              exit 1
            fi
            if [ -n "$FSS_ARCHIVED_SYSTEM_FAILURES" ]; then
              printf "%s" "$FSS_VERDICT_TAGS" | grep -E "PRE_ACTIVATION_ARCHIVE|RECOVERY_ARCHIVE|PRE_FSS_ARCHIVE"
            fi
          '
        """)

    ${fssVerificationTest { }}

    print("All FSS tests completed successfully")
  '';
}
