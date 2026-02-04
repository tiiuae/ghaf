# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Hardware information generation service for host systems
#
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.ghaf.services.hwinfo;
in
{
  _file = ./host.nix;

  options.ghaf.services.hwinfo = {
    enable = lib.mkEnableOption "hardware information generation service";

    outputDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/ghaf-hwinfo";
      description = "Directory where hardware information files will be stored";
    };

    format = lib.mkOption {
      type = lib.types.enum [ "json" ];
      default = "json";
      description = "Output format for hardware information";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.ghaf-hwinfo-generate = {
      description = "Generate hardware information files";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "systemd-hostnamed.service"
        "systemd-timesyncd.service"
      ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = "ghaf-hwinfo";
        StateDirectoryMode = "0755";
      };

      script = lib.getExe (
        pkgs.writeShellApplication {
          name = "hwinfo-generate-script";
          runtimeInputs = with pkgs; [
            nvme-cli
            iproute2
            jq
            coreutils
          ];
          text = ''
            set -euo pipefail

            # Ensure output directory exists
            mkdir -p ${cfg.outputDir}

            # Detect NVMe serial number
            NVME_SERIAL=""
            if command -v nvme >/dev/null 2>&1; then
              # Try multiple methods to get NVMe serial
              NVME_SERIAL=$(nvme list -o json 2>/dev/null | jq -r '.Devices[0].SerialNumber // empty' || true)

              if [ -z "$NVME_SERIAL" ]; then
                # Fallback to direct device query
                for dev in /dev/nvme*n1; do
                  if [ -e "$dev" ]; then
                    NVME_SERIAL=$(nvme id-ctrl "$dev" 2>/dev/null | grep -E "^sn\s*:" | awk '{print $3}' || true)
                    [ -n "$NVME_SERIAL" ] && break
                  fi
                done
              fi
            fi

            # Detect MAC address
            MAC_ADDR=""
            if command -v ip >/dev/null 2>&1; then
              # Get first non-loopback interface MAC
              MAC_ADDR=$(ip -j link show 2>/dev/null | jq -r '.[] | select(.operstate == "UP" and .link_type != "loopback") | .address' | head -1 || true)

              if [ -z "$MAC_ADDR" ]; then
                # Fallback to any interface with MAC
                MAC_ADDR=$(ip -j link show 2>/dev/null | jq -r '.[] | select(.address != null and .link_type != "loopback") | .address' | head -1 || true)
              fi
            fi

            # Get hostname with fallback
            HOSTNAME=$(hostname 2>/dev/null || echo "")
            if [ -z "$HOSTNAME" ] || [ "$HOSTNAME" = "localhost" ]; then
              HOSTNAME=$(cat /etc/hostname 2>/dev/null || echo "")
            fi

            # Generate JSON output using jq
            jq -n \
              --arg nvme_serial "$NVME_SERIAL" \
              --arg mac_address "$MAC_ADDR" \
              --arg hostname "$HOSTNAME" \
              --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
              '{
                nvme_serial: $nvme_serial,
                mac_address: $mac_address,
                hostname: $hostname,
                timestamp: $timestamp
              }' > ${cfg.outputDir}/hwinfo.json

            echo "Hardware info JSON generated at ${cfg.outputDir}/hwinfo.json"

            # Generate metadata using jq
            jq -n \
              --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
              --arg hostname "$HOSTNAME" \
              --arg output_dir "${cfg.outputDir}" \
              --arg system "${pkgs.stdenv.hostPlatform.system}" \
              '{
                generated_at: $generated_at,
                hostname: $hostname,
                output_dir: $output_dir,
                system: $system
              }' > ${cfg.outputDir}/metadata.json
          '';
        }
      );
    };

    # Create convenience command for manual generation
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "ghaf-hwinfo-generate";
        runtimeInputs = [ pkgs.systemd ];
        text = ''
          echo "Regenerating hardware information..."
          systemctl restart ghaf-hwinfo-generate.service
          systemctl status ghaf-hwinfo-generate.service --no-pager
        '';
      })
    ];
  };
}
