# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Configuration for NVIDIA Jetson Orin AGX/NX reference boards
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.orin;
  rtcSeedMaxAheadSeconds = 180 * 24 * 60 * 60;
  rtcSeedMinEpochSeconds = 1704067200; # 2024-01-01T00:00:00Z
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    ;
in
{
  _file = ./jetson-orin.nix;

  options.ghaf.hardware.nvidia.orin = {
    # Enable the Orin boards
    enable = mkEnableOption "Orin hardware";

    flashScriptOverrides.onlyQSPI = mkEnableOption "to only flash QSPI partitions, i.e. disable flashing of boot and root partitions to eMMC";

    flashScriptOverrides.preFlashCommands = mkOption {
      description = "Commands to run before the actual flashing";
      type = types.str;
      default = "";
    };

    somType = mkOption {
      description = "SoM config Type (NX|AGX32|AGX64|Nano)";
      type = types.str;
      default = "agx";
    };

    carrierBoard = mkOption {
      description = "Board Type";
      type = types.str;
      default = "devkit";
    };

    kernelVersion = mkOption {
      description = "Kernel version";
      type = types.str;
      default = "bsp-default";
    };
  };

  config = mkIf cfg.enable {
    hardware.nvidia-jetpack.kernel.version = "${cfg.kernelVersion}";
    nixpkgs.hostPlatform.system = "aarch64-linux";

    ghaf.hardware = {
      aarch64.systemd-boot-dtb.enable = true;
      passthrough = {
        vhotplug.enable = true;
        usbQuirks.enable = true;
      };
    };

    boot = {
      loader = {
        efi.canTouchEfiVariables = true;
        systemd-boot.enable = true;
      };

      modprobeConfig.enable = true;

      kernelPatches = [
        {
          name = "vsock-config";
          patch = null;
          structuredExtraConfig = with lib.kernel; {
            VHOST = yes;
            VHOST_MENU = yes;
            VHOST_IOTLB = yes;
            VHOST_VSOCK = yes;
            VSOCKETS = yes;
            VSOCKETS_DIAG = yes;
            VSOCKETS_LOOPBACK = yes;
            VIRTIO_VSOCKETS_COMMON = yes;
          };
        }
        {
          name = "disable-rtc-hctosys";
          patch = null;
          structuredExtraConfig = with lib.kernel; {
            RTC_HCTOSYS = lib.mkForce no;
          };
        }
      ];
    };

    services.udev.extraRules = ''
      SUBSYSTEM=="rtc", KERNEL=="rtc0", TEST=="/var/lib/systemd/timesync/clock", TAG+="systemd", ENV{SYSTEMD_WANTS}+="ghaf-seed-time-from-rtc@%k.service"
    '';

    systemd.services."ghaf-seed-time-from-rtc@" = {
      description = "Seed system time from plausible RTC value (%I)";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = false;
      };
      script = ''
        set -eu

        rtc_device="$1"
        rtc_since_epoch_path="/sys/class/rtc/$rtc_device/since_epoch"
        anchor_path="/var/lib/systemd/timesync/clock"
        max_ahead_seconds=${toString rtcSeedMaxAheadSeconds}
        min_epoch_seconds=${toString rtcSeedMinEpochSeconds}

        if [ ! -e "$anchor_path" ]; then
          echo "RTC seed skipped: $anchor_path is missing"
          exit 0
        fi

        if [ ! -r "$rtc_since_epoch_path" ]; then
          echo "RTC seed skipped: $rtc_since_epoch_path not readable"
          exit 0
        fi

        rtc_epoch="$(${pkgs.coreutils}/bin/tr -d '\n' < "$rtc_since_epoch_path")"
        if ! [[ "$rtc_epoch" =~ ^[0-9]+$ ]]; then
          echo "RTC seed skipped: non-numeric RTC epoch '$rtc_epoch'"
          exit 0
        fi

        if [ "$rtc_epoch" -lt "$min_epoch_seconds" ]; then
          echo "RTC seed skipped: RTC epoch $rtc_epoch below minimum $min_epoch_seconds"
          exit 0
        fi

        anchor_epoch="$(${pkgs.coreutils}/bin/stat -c %Y "$anchor_path" 2>/dev/null || echo 0)"
        if ! [[ "$anchor_epoch" =~ ^[0-9]+$ ]]; then
          echo "RTC seed skipped: invalid anchor mtime '$anchor_epoch'"
          exit 0
        fi

        if [ "$anchor_epoch" -le 0 ]; then
          echo "RTC seed skipped: anchor mtime is not positive ($anchor_epoch)"
          exit 0
        fi

        if [ "$rtc_epoch" -lt "$anchor_epoch" ]; then
          echo "RTC seed skipped: RTC epoch $rtc_epoch is behind anchor $anchor_epoch"
          exit 0
        fi

        ahead_seconds=$((rtc_epoch - anchor_epoch))
        if [ "$ahead_seconds" -gt "$max_ahead_seconds" ]; then
          echo "RTC seed skipped: RTC ahead by $ahead_seconds seconds (> $max_ahead_seconds)"
          exit 0
        fi

        current_epoch="$(${pkgs.coreutils}/bin/date -u +%s)"
        if [ "$rtc_epoch" -le "$current_epoch" ]; then
          echo "RTC seed skipped: system time already >= RTC (now=$current_epoch rtc=$rtc_epoch)"
          exit 0
        fi

        ${pkgs.coreutils}/bin/date -u -s "@$rtc_epoch" >/dev/null
        echo "RTC seed applied: system time set to epoch $rtc_epoch from $rtc_device"
      '';
      scriptArgs = "%i";
    };

    services.nvpmodel = {
      enable = lib.mkDefault true;
      # Enable all CPU cores, full power consumption (50W on AGX, 25W on NX)
      profileNumber = lib.mkDefault 3;
    };
    hardware.deviceTree = {
      enable = lib.mkDefault true;
      # Add the include paths to build the dtb overlays
      dtboBuildExtraIncludePaths = [
        "${lib.getDev config.hardware.deviceTree.kernelPackage}/lib/modules/${config.hardware.deviceTree.kernelPackage.modDirVersion}/source/nvidia/soc/t23x/kernel-include"
      ];
    };

    # NOTE: "-nv.dtb" files are from NVIDIA's BSP
    # Versions of the device tree without PCI passthrough related
    # modifications.
  };
}
