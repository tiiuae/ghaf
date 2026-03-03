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

      # Use TPM resource manager device only.
      tcti="device:/dev/tpmrm0"
      dev="''${tcti##*:}"
      echo "Trying $dev ..."
      export TPM2TOOLS_TCTI="$tcti"

      echo "Attempting owner hierarchy recovery via platform hierarchy on $dev"

      # Try re-enabling owner and endorsement hierarchies via PH
      if tpm2_hierarchycontrol -C platform ownerEnable set 2>/dev/null; then
        echo "Owner hierarchy re-enabled via $dev"
        tpm2_hierarchycontrol -C platform endorseEnable set 2>/dev/null \
          && echo "Endorsement hierarchy re-enabled via $dev" \
          || echo "WARNING: Could not re-enable endorsement hierarchy via $dev"

        exit 0
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

      echo "WARNING: Could not re-enable owner hierarchy on any device"
      echo "VMs will fall back to non-TPM methods where possible"
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
      pkcs11.enable = pkgs.stdenv.isx86_64 || pkgs.stdenv.isAarch64;
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
