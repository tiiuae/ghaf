# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Hardware information reading tools for guest VMs
#
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.ghaf.services.hwinfo-guest;
in
{
  _file = ./guest.nix;

  options.ghaf.services.hwinfo-guest = {
    enable = lib.mkEnableOption "hardware information reading tools for guest VMs";
  };

  config = lib.mkIf cfg.enable {
    # Ensure necessary kernel modules are loaded
    boot.kernelModules = [ "qemu_fw_cfg" ];

    environment.systemPackages = [
      # Hardware info reader using fw_cfg
      (pkgs.writeShellApplication {
        name = "ghaf-read-hwinfo";
        runtimeInputs = with pkgs; [
          jq
          coreutils
          kmod
          findutils
        ];
        text = ''
          set -euo pipefail

          # Check possible fw_cfg paths
          FW_CFG_PATHS=(
            "/sys/firmware/qemu_fw_cfg/by_name/opt/com.ghaf.hwinfo/raw"
            "/sys/firmware/qemu_fw_cfg/by_name/opt/com.ghaf.hwinfo/data"
          )

          for path in "''${FW_CFG_PATHS[@]}"; do
            if [ -f "$path" ]; then
              echo "Hardware Information:"
              jq . < "$path" || cat "$path"
              exit 0
            fi
          done

          # Not found - provide helpful error
          echo "Hardware information not available" >&2

          if ! lsmod | grep -q qemu_fw_cfg; then
            echo "Note: fw_cfg kernel module not loaded. Try: sudo modprobe qemu_fw_cfg" >&2
          elif [ ! -d "/sys/firmware/qemu_fw_cfg" ]; then
            echo "Note: fw_cfg sysfs interface not available" >&2
          else
            echo "Note: Hardware info file not found in fw_cfg" >&2
            echo "Available fw_cfg entries:" >&2
            find /sys/firmware/qemu_fw_cfg/by_name/ -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | head -10 >&2
          fi

          exit 1
        '';
      })

      # Convenience aliases
      (pkgs.writeShellApplication {
        name = "read-hwinfo";
        runtimeInputs = [ ];
        text = ''
          exec ghaf-read-hwinfo "$@"
        '';
      })
    ];

    # Create systemd service to log hardware info at boot (optional)
    systemd.services.ghaf-hwinfo-log = {
      description = "Log hardware information at boot";
      after = [ "multi-user.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StandardOutput = "journal";
      };

      script = lib.getExe (
        pkgs.writeShellApplication {
          name = "hwinfo-log-script";
          runtimeInputs = [ ];
          text = ''
            echo "Attempting to read hardware information..."
            ghaf-read-hwinfo || echo "Failed to read hardware information"
          '';
        }
      );
    };
  };
}
