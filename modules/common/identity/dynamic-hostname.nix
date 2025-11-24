# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    escapeShellArg
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.ghaf.identity.dynamicHostName;

  computeScript = pkgs.writeShellApplication {
    name = "ghaf-compute-hostname";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.util-linux
    ];
    text = ''

      prefix=${escapeShellArg cfg.prefix}
      outDir=${escapeShellArg (toString cfg.outputDir)}
      shareDir=${escapeShellArg (toString cfg.shareDir)}
      digits=${toString cfg.digits}
      source=${escapeShellArg cfg.source}
      staticValue=${escapeShellArg (cfg.staticValue or "")}

      mkdir -p "$outDir" "$shareDir"

      read_hardware_id() {
        ids=""

        # Collect DMI serial/UUID
        for p in /sys/class/dmi/id/product_serial /sys/class/dmi/id/product_uuid; do
          if [ -r "$p" ]; then
            v=$(tr -cd '[:alnum:]' <"$p")
            if [ -n "$v" ]; then
              ids="''${ids}''${v}"
            fi
          fi
        done

        # Collect disk hardware IDs (serial-based, not filesystem UUIDs)
        for disk in /dev/disk/by-id/*; do
          if [ -L "$disk" ]; then
            # Skip partition entries, USB devices, and DM devices
            diskid=$(basename "$disk")
            if [[ ! "$diskid" =~ -part[0-9]+$ ]] && \
               [[ ! "$diskid" =~ ^usb- ]] && \
               [[ ! "$diskid" =~ ^dm- ]]; then
              ids="''${ids}''${diskid}"
            fi
          fi
        done 2>/dev/null

        # Get MACs from physical network interfaces only
        for iface in /sys/class/net/*; do
          ifname=$(basename "$iface")

          # Skip loopback
          if [[ "$ifname" == "lo" ]]; then
            continue
          fi

          # Must have device backing
          if [[ -L "$iface/device" ]]; then
            device_path=$(readlink -f "$iface/device")

            # Exclude USB gadget mode (device mode, not host mode)
            if [[ "$device_path" =~ /gadget ]]; then
              continue
            fi

            # Include if on physical bus (check path for bus type)
            if [[ "$device_path" =~ /(pci|platform|amba|sdio|mmc)/ ]] || \
               [[ "$device_path" =~ /usb/ && ! "$device_path" =~ /gadget ]]; then

              mac=$(cat "$iface/address" 2>/dev/null)
              if [[ -n "$mac" && "$mac" != "00:00:00:00:00:00" ]]; then
                ids="''${ids}''${mac}"
              fi
            fi
          fi
        done

        # Fallback to machine-id only if no other IDs were collected
        if [ -z "$ids" ] && [ -r /etc/machine-id ]; then
          ids="$(cat /etc/machine-id)"
        fi

        if [ -n "$ids" ]; then
          echo "$ids"
          return 0
        fi

        return 1
      }

      # Get hardware key based on configured source
      case "$source" in
        static)
          if [ -z "$staticValue" ]; then
            echo "Error: source is 'static' but staticValue is not set" >&2
            exit 1
          fi
          key="$staticValue"
          ;;
        random)
          # Generate random value on first boot, persist it
          randomFile="$outDir/random-seed"
          if [ ! -f "$randomFile" ]; then
            od -txC -An -N16 /dev/urandom | tr -d ' \n' > "$randomFile"
          fi
          key=$(cat "$randomFile")
          ;;
        hardware)
          key=$(read_hardware_id || echo "fallback")
          ;;
        *)
          echo "Error: unknown source '$source'" >&2
          exit 1
          ;;
      esac

      # Use cksum (CRC32) and map to N decimal digits, zero-padded
      crc=$(cksum <<<"$key" | cut -d' ' -f1)
      # Calculate modulo 10^digits using ** operator
      mod=$((10 ** digits))
      id=$(printf "%0''${digits}d" $((crc % mod)))

      name="''${prefix}-''${id}"

      printf "%s" "$name" | tee "$outDir/hostname" "$shareDir/hostname" >/dev/null
      printf "%s" "$id" | tee "$outDir/id" "$shareDir/id" > /dev/null

      ln -sf "$outDir/hostname" /run/ghaf-hostname

      # Generate device-id from our hardware-derived ID (for backward compatibility)
      # Use the same ID but format as hex string with dashes like: 00-01-23-45-67
      printf "%010x" "$((10#$id))" | fold -w2 | paste -sd'-' | tr -d '\n' > "$shareDir/../device-id"
    '';
  };
in
{
  options.ghaf.identity.dynamicHostName = {
    enable = mkEnableOption "runtime human-readable hostname derived from hardware";

    source = mkOption {
      type = types.enum [
        "hardware"
        "static"
        "random"
      ];
      default = "hardware";
      description = ''
        Source for generating the hardware ID:
        - hardware: Best-effort hardware detection (DMI, disk hardware ID, MAC, machine-id)
        - static: Use user-provided static value
        - random: Generate random value on first boot (persisted)
      '';
    };

    staticValue = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Static hardware ID value (only used when source = 'static')";
    };

    prefix = mkOption {
      type = types.str;
      default = "ghaf";
      description = "Hostname prefix";
    };

    digits = mkOption {
      type = types.int;
      default = 10;
      description = "Number of decimal digits";
    };

    shareDir = mkOption {
      type = types.path;
      default = "/persist/common/ghaf";
      description = "Shared dir exposed to VMs (is available under /etc/common in VMs)";
    };

    outputDir = mkOption {
      type = types.path;
      default = "/var/lib/ghaf/identity";
      description = "Private host-only output dir";
    };
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${toString cfg.outputDir} 0755 root root - -"
      "d ${toString cfg.shareDir} 0755 root root - -"
      "d /persist/common 0755 root root - -"
    ];

    systemd.services.ghaf-dynamic-hostname = {
      description = "Compute and export dynamic host identity and transient hostname";
      wantedBy = [ "multi-user.target" ];
      after = [
        "local-fs.target"
        "sysinit.target"
      ];
      before = [
        "multi-user.target"
        "network-online.target"
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${computeScript}/bin/ghaf-compute-hostname";
        RemainAfterExit = true;
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
      let
        setHostnameEnv = pkgs.writeShellApplication {
          name = "set-hostname-env";
          runtimeInputs = [ pkgs.systemd ];
          text = ''
            if [ -r ${toString cfg.outputDir}/hostname ]; then
              if command -v systemctl >/dev/null 2>&1; then
                systemctl set-environment GHAF_HOSTNAME="$(cat ${toString cfg.outputDir}/hostname)"
              fi
            fi
          '';
        };
      in
      "${setHostnameEnv}/bin/set-hostname-env";
  };
}
