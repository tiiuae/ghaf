# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.hardware.tpm2;

  tpmHierarchyUnlockScript = pkgs.writeShellApplication {
    name = "tpm-hierarchy-unlock";
    runtimeInputs = [
      pkgs.tpm2-tools
      pkgs.coreutils
    ];
    text = ''
      FLAG="/var/lib/tpm-cleared"

      # Try both TCTI devices — resource manager first, then direct
      for tcti in "device:/dev/tpmrm0" "device:/dev/tpm0"; do
        dev="''${tcti##*:}"
        echo "Trying $dev ..."
        export TPM2TOOLS_TCTI="$tcti"

        # Test if owner hierarchy is usable on this device
        if tpm2_createprimary -C owner -c /tmp/tpm-test.ctx -Q 2>/dev/null; then
          rm -f /tmp/tpm-test.ctx
          echo "TPM owner hierarchy is accessible via $dev"
          exit 0
        fi

        echo "Owner hierarchy locked on $dev — attempting recovery via platform hierarchy"

        # Try re-enabling owner and endorsement hierarchies via PH
        if tpm2_hierarchycontrol -C platform ownerEnable set 2>/dev/null; then
          echo "Owner hierarchy re-enabled via $dev"
          tpm2_hierarchycontrol -C platform endorseEnable set 2>/dev/null \
            && echo "Endorsement hierarchy re-enabled via $dev" \
            || echo "WARNING: Could not re-enable endorsement hierarchy via $dev"

          # Verify createprimary works after re-enable
          if tpm2_createprimary -C owner -c /tmp/tpm-test.ctx -Q 2>/dev/null; then
            rm -f /tmp/tpm-test.ctx
            echo "Owner hierarchy confirmed working after re-enable"
            exit 0
          fi
          rm -f /tmp/tpm-test.ctx
          echo "Owner hierarchy still not usable after re-enable"
        fi

        # Last resort: factory-reset TPM via platform hierarchy.
        # This clears unknown auth values left by a previous OS installation.
        # Only attempt once — the flag file prevents repeated clears.
        if [ ! -f "$FLAG" ]; then
          echo "Attempting TPM factory reset via platform hierarchy on $dev ..."
          if tpm2_clear -c platform 2>/dev/null; then
            echo "TPM factory reset successful — all auth values cleared"
            mkdir -p "$(dirname "$FLAG")"
            date -Iseconds > "$FLAG"
            # After clear, hierarchies are re-enabled with empty auth
            exit 0
          else
            echo "TPM factory reset failed on $dev"
          fi
        fi

        echo "Platform hierarchy also locked on $dev"
      done

      echo "WARNING: Could not re-enable owner hierarchy on any device"
      echo "VMs will fall back to non-TPM methods where possible"
    '';
  };

  tpmHierarchyMonitorScript = pkgs.writeShellApplication {
    name = "tpm-hierarchy-monitor";
    runtimeInputs = [
      pkgs.tpm2-tools
      pkgs.coreutils
      pkgs.psmisc # fuser
    ];
    text = ''
      LOG="/tmp/tpm-hierarchy-monitor.log"
      echo "=== TPM hierarchy monitor starting at $(date -Iseconds) ===" > "$LOG"
      for i in $(seq 1 60); do
        {
          echo "--- t=$i $(date -Iseconds) ---"

          echo "=== /dev/tpm0 (direct) ==="
          TPM2TOOLS_TCTI="device:/dev/tpm0" tpm2_getcap properties-variable 2>&1 \
            | grep -iE "(enable|lockout)" || echo "(tpm0 getcap failed)"

          echo "=== /dev/tpmrm0 (resource manager) ==="
          TPM2TOOLS_TCTI="device:/dev/tpmrm0" tpm2_getcap properties-variable 2>&1 \
            | grep -iE "(enable|lockout)" || echo "(tpmrm0 getcap failed)"

          echo "=== createprimary test ==="
          TPM2TOOLS_TCTI="device:/dev/tpm0" tpm2_createprimary -C owner -c /tmp/tpm-test-tpm0.ctx -Q 2>&1 \
            && echo "tpm0:owner=OK" || echo "tpm0:owner=FAIL"
          rm -f /tmp/tpm-test-tpm0.ctx
          TPM2TOOLS_TCTI="device:/dev/tpmrm0" tpm2_createprimary -C owner -c /tmp/tpm-test-tpmrm0.ctx -Q 2>&1 \
            && echo "tpmrm0:owner=OK" || echo "tpmrm0:owner=FAIL"
          rm -f /tmp/tpm-test-tpmrm0.ctx

          echo "=== TPM device users ==="
          fuser /dev/tpm0 /dev/tpmrm0 2>&1 || true
        } >> "$LOG"
        sleep 1
      done
      echo "=== Monitor complete ===" >> "$LOG"
    '';
  };
in
{
  _file = ./tpm2.nix;

  options.ghaf.hardware.tpm2 = {
    enable = lib.mkEnableOption "TPM2 PKCS#11 interface";
  };

  config = lib.mkIf cfg.enable {
    security.tpm2 = {
      enable = true;
      # tpm2-pkcs11 cross-compilation is broken on aarch64 (tpm2-pytss patch conflict)
      pkcs11.enable = pkgs.stdenv.isx86_64;
      abrmd.enable = false;
    };

    environment.systemPackages = lib.mkIf config.ghaf.profiles.debug.enable [
      pkgs.opensc
      pkgs.tpm2-tools
    ];

    assertions = [
      {
        assertion = pkgs.stdenv.isx86_64 || pkgs.stdenv.isAarch64;
        message = "TPM2 is only supported on x86_64 and aarch64";
      }
    ];

    systemd.services = {
      # After LUKS unlock the owner hierarchy may be disabled/locked.
      # Re-enable it before VMs start so their TPM operations succeed.
      tpm-hierarchy-unlock = {
        description = "Re-enable TPM owner hierarchy after LUKS unlock";
        after = [
          "systemd-cryptsetup.target"
          "systemd-tpm2-setup.service"
        ];
        before = [ "microvms.target" ];
        wantedBy = [ "microvms.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = lib.getExe tpmHierarchyUnlockScript;
        };
      };

      # Diagnostic: log hierarchy state every second for 60s starting before unlock.
      # Check /tmp/tpm-hierarchy-monitor.log to compare /dev/tpm0 vs /dev/tpmrm0.
      tpm-hierarchy-monitor = lib.mkIf config.ghaf.profiles.debug.enable {
        description = "Monitor TPM hierarchy state during boot";
        after = [
          "systemd-cryptsetup.target"
          "dev-tpm0.device"
        ];
        before = [ "tpm-hierarchy-unlock.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = lib.getExe tpmHierarchyMonitorScript;
        };
      };

      # Re-enable owner hierarchy after VMs have started, in case VM initrd
      # LUKS operations locked it again.
      tpm-hierarchy-unlock-late = {
        description = "Re-enable TPM owner hierarchy after VM boot";
        after = [ "microvms.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # Wait for VM initrd LUKS operations to complete
          ExecStartPre = "${pkgs.coreutils}/bin/sleep 10";
          ExecStart = lib.getExe tpmHierarchyUnlockScript;
        };
      };
    };
  };
}
