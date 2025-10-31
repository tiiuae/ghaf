# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.identity.dynamicHostName;

  computeScript = pkgs.writeShellScript "ghaf-compute-hostname" ''
    set -euo pipefail

    PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.iproute2
        pkgs.gawk
        pkgs.gnugrep
      ]
    }:$PATH

    prefix=${lib.escapeShellArg cfg.prefix}
    outDir=${lib.escapeShellArg (toString cfg.outputDir)}
    shareDir=${lib.escapeShellArg (toString cfg.shareDir)}
    digits=${toString cfg.digits}

    mkdir -p "$outDir" "$shareDir"

    read_dmi() {
      for p in /sys/class/dmi/id/product_serial /sys/class/dmi/id/product_uuid; do
        if [ -r "$p" ]; then
          v=$(tr -cd '[:alnum:]' <"$p")
          if [ -n "$v" ]; then
            echo "$v"; return 0
          fi
        fi
      done
      return 1
    }

    read_mac() {
      ${pkgs.iproute2}/bin/ip -o link show \
        | ${pkgs.gawk}/bin/awk -F': ' '$2 !~ /lo/ {print $2}' \
        | while read -r ifc; do
            [ -r "/sys/class/net/$ifc/address" ] && cat "/sys/class/net/$ifc/address"
          done \
        | ${pkgs.gnugrep}/bin/grep -vi '^00:00:00:00:00:00$' | sort | head -n1
    }

    key=""
    key=$(read_dmi || true)
    if [ -z "$key" ]; then
      key=$(read_mac || true)
    fi
    if [ -z "$key" ] && [ -r /etc/machine-id ]; then
      key=$(cat /etc/machine-id)
    fi
    if [ -z "$key" ]; then
      key="fallback"
    fi

    # Use cksum (CRC32) and map to N decimal digits, zero-padded
    id=$(${pkgs.coreutils}/bin/cksum <<<"$key" | ${pkgs.gawk}/bin/awk -v d="$digits" '{ n=$1; m=1; for(i=0;i<d;i++) m*=10; printf "%0*d\n", d, n % m }')

    name="''${prefix}-''${id}"

    printf "%s\n" "$name" | tee "$outDir/hostname" > /dev/null
    printf "%s\n" "$id" > "$outDir/id"

    ln -sf "$outDir/hostname" /run/ghaf-hostname

    printf "%s\n" "$name" | tee "$shareDir/hostname" > /dev/null
    printf "%s\n" "$id" > "$shareDir/id"
  '';
in
{
  options.ghaf.identity.dynamicHostName = {
    enable = lib.mkEnableOption "Runtime human-readable hostname derived from hardware";
    prefix = lib.mkOption {
      type = lib.types.str;
      default = "ghaf";
      description = "Hostname prefix";
    };
    digits = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Number of decimal digits";
    };
    shareDir = lib.mkOption {
      type = lib.types.path;
      default = "/persist/common/ghaf";
      description = "Shared dir exposed to VMs (is available under /etc/common in VMs)";
    };
    outputDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/ghaf/identity";
      description = "Private host-only output dir";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${toString cfg.outputDir} 0755 root root - -"
      "d ${toString cfg.shareDir} 0755 root root - -"
    ];

    systemd.services.ghaf-dynamic-hostname = {
      description = "Compute and export dynamic host identity and transient hostname";
      wantedBy = [ "multi-user.target" ];
      after = [
        "local-fs.target"
        "sysinit.target"
      ];
      before = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = computeScript;
      };
    };

    # Set environment via PAM
    environment.extraInit = ''
      if [ -r /run/ghaf-hostname ]; then
        export GHAF_HOSTNAME="$(cat /run/ghaf-hostname)"
        export GHAF_HOSTNAME_FILE="/run/ghaf-hostname"
      fi
    '';

    # Set systemd environment for services
    systemd.services.ghaf-dynamic-hostname.serviceConfig.ExecStartPost =
      pkgs.writeShellScript "set-hostname-env" ''
        if [ -r ${toString cfg.outputDir}/hostname ]; then
          if command -v systemctl >/dev/null 2>&1; then
            systemctl set-environment GHAF_HOSTNAME="$(cat ${toString cfg.outputDir}/hostname)" 2>/dev/null || true
          fi
        fi
      '';
  };
}
