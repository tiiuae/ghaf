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

  rtcSeedAnchorPath = "/var/lib/systemd/timesync/clock";
  rtcSeedMaxAheadSeconds = 180 * 24 * 60 * 60;
  rtcSeedMinEpochSeconds = 1704067200; # 2024-01-01T00:00:00Z
  rtcSeedTimeFromRtc = pkgs.writeShellApplication {
    name = "ghaf-seed-time-from-rtc";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      rtc_device="$1"
      rtc_since_epoch_path="/sys/class/rtc/$rtc_device/since_epoch"
      anchor_path=${lib.escapeShellArg rtcSeedAnchorPath}
      max_ahead_seconds=${toString rtcSeedMaxAheadSeconds}
      min_epoch_seconds=${toString rtcSeedMinEpochSeconds}

      skip() {
        echo "RTC seed skipped: $*"
        exit 0
      }

      if [ ! -f "$anchor_path" ]; then
        skip "$anchor_path is missing or not a regular file"
      fi

      if [ ! -r "$rtc_since_epoch_path" ]; then
        skip "$rtc_since_epoch_path not readable"
      fi

      rtc_epoch="$(tr -d '\n' < "$rtc_since_epoch_path")"
      if ! [[ "$rtc_epoch" =~ ^[0-9]+$ ]]; then
        skip "non-numeric RTC epoch '$rtc_epoch'"
      fi

      if [ "$rtc_epoch" -lt "$min_epoch_seconds" ]; then
        skip "RTC epoch $rtc_epoch below minimum $min_epoch_seconds"
      fi

      anchor_epoch="$(stat -c %Y "$anchor_path" 2>/dev/null || echo 0)"
      if ! [[ "$anchor_epoch" =~ ^[0-9]+$ ]]; then
        skip "invalid anchor mtime '$anchor_epoch'"
      fi

      if [ "$anchor_epoch" -le 0 ]; then
        skip "anchor mtime is not positive ($anchor_epoch)"
      fi

      if [ "$rtc_epoch" -lt "$anchor_epoch" ]; then
        skip "RTC epoch $rtc_epoch is behind anchor $anchor_epoch"
      fi

      ahead_seconds=$((rtc_epoch - anchor_epoch))
      if [ "$ahead_seconds" -gt "$max_ahead_seconds" ]; then
        skip "RTC ahead by $ahead_seconds seconds (> $max_ahead_seconds)"
      fi

      current_epoch="$(date -u +%s)"
      if [ "$rtc_epoch" -le "$current_epoch" ]; then
        skip "system time already >= RTC (now=$current_epoch rtc=$rtc_epoch)"
      fi

      date -u -s "@$rtc_epoch" >/dev/null
      echo "RTC seed applied: system time set to epoch $rtc_epoch from $rtc_device"
    '';
  };

  provisionEkCertsApp = pkgs.writeShellApplication {
    name = "ghaf-provision-ek-certs";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.nvidia-jetpack.ftpmHelper
      pkgs.nvidia-jetpack.ftpmSimTooling
      pkgs.openssl
      pkgs.tpm2-tools
    ];
    text = ''
      set -euo pipefail

      export TPM2TOOLS_TCTI="device:/dev/tpmrm0"

      RSA_EK_CERT_HANDLE="0x01C00002"
      ECC_EK_CERT_HANDLE="0x01C0000A"

      if timeout 5s tpm2_nvreadpublic "$RSA_EK_CERT_HANDLE" >/dev/null 2>&1 &&
        timeout 5s tpm2_nvreadpublic "$ECC_EK_CERT_HANDLE" >/dev/null 2>&1; then
        echo "EK cert NV indices already present, skipping provisioning"
        exit 0
      fi

      export PATH="${pkgs.nvidia-jetpack.ftpmHelper}/bin:$PATH"

      # NVIDIA SIM tool expects to run from its own tree where ./conf exists.
      # This is for unfused development/testing flow, not production provisioning.
      ${pkgs.nvidia-jetpack.ftpmSimTooling}/bin/ftpm_sim_provisioning_tool.sh ek_prov

      if ! timeout 5s tpm2_nvreadpublic "$RSA_EK_CERT_HANDLE" >/dev/null 2>&1 ||
        ! timeout 5s tpm2_nvreadpublic "$ECC_EK_CERT_HANDLE" >/dev/null 2>&1; then
        echo "NVIDIA SIM provisioning did not produce expected EK NV indices" >&2
        exit 1
      fi

      echo "Provisioned fTPM EK certs using NVIDIA SIM tooling"
    '';
  };

  exportEkBundleApp = pkgs.writeShellApplication {
    name = "ghaf-export-ek-endorsement-bundle";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.openssl
      pkgs.tpm2-tools
    ];
    text = ''
      set -euo pipefail

      export TPM2TOOLS_TCTI="device:/dev/tpmrm0"

      EK_NV_RSA="0x01C00002"
      EK_NV_ECC="0x01C0000A"
      WORKDIR="/run/ghaf-ek-export"
      OUTDIR="/persist/common/spire/ca"
      BUNDLE="${"$"}OUTDIR/endorsement-bundle.pem"
      BUNDLE_TMP="$WORKDIR/endorsement-bundle.pem"
      EXPORTED_ANY=0

      cleanup() {
        rm -rf "$WORKDIR"
      }
      trap cleanup EXIT

      mkdir -p "$WORKDIR" "$OUTDIR"
      chmod 0755 /persist/common /persist/common/spire "$OUTDIR"
      : > "$BUNDLE_TMP"

      export_one() {
        local idx="$1"
        local pem="$2"
        local der
        der="$WORKDIR/$(basename "$pem" .pem).der"

        if ! timeout 5s tpm2_nvreadpublic "$idx" >/dev/null 2>&1; then
          echo "EK index $idx missing, skipping export"
          return 0
        fi

        timeout 8s tpm2_nvread "$idx" -o "$der"
        openssl x509 -inform DER -in "$der" -out "$pem"
        chmod 0644 "$pem"
        cat "$pem" >> "$BUNDLE_TMP"
        EXPORTED_ANY=1
      }

      export_one "$EK_NV_RSA" "$OUTDIR/ek-rsa.pem"
      export_one "$EK_NV_ECC" "$OUTDIR/ek-ecc.pem"

      if [ "$EXPORTED_ANY" -eq 0 ]; then
        echo "No EK certs exported, preserving existing endorsement bundle"
        exit 0
      fi

      cp "$BUNDLE_TMP" "$BUNDLE"
      chmod 0644 "$BUNDLE"
      echo "Wrote endorsement bundle to $BUNDLE"
    '';
  };

  loadFtpmModuleApp = pkgs.writeShellApplication {
    name = "ghaf-load-ftpm-module";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.kmod
      pkgs.systemd
    ];
    text = ''
      set -euo pipefail

      if [ -e /dev/tpmrm0 ]; then
        echo "fTPM device already present, skipping"
        exit 0
      fi

      if ! systemctl is-active --quiet tee-supplicant.service; then
        echo "tee-supplicant is not active" >&2
        exit 1
      fi

      if ! timeout 20s modprobe tpm_ftpm_tee; then
        echo "Failed to load tpm_ftpm_tee" >&2
        exit 1
      fi

      udevadm settle --timeout=5 || true
      if [ ! -e /dev/tpmrm0 ]; then
        echo "tpm_ftpm_tee loaded but /dev/tpmrm0 is missing" >&2
        exit 1
      fi

      echo "Loaded tpm_ftpm_tee"
    '';
  };

  firmwareEkbImage =
    pkgs.buildPackages.runCommand "ghaf-eks-t234"
      {
        nativeBuildInputs = [
          pkgs.buildPackages.openssl
          pkgs.buildPackages.nvidia-jetpack.genEkb
        ];
      }
      ''
                set -euo pipefail

                mkdir -p "$out"

                # Development key for unfused devices (OEM_K1 all-zero key).
        printf '%s' "0x0000000000000000000000000000000000000000000000000000000000000000" > oem_k1.key

        # Avoid interactive prompt in gen_ekb.py by providing UEFI auth key.
        printf '%s' "0x00000000000000000000000000000000" > auth.key

                openssl req -x509 -newkey rsa:2048 -sha256 -nodes \
                  -keyout ek-rsa-key.pem -out ek-rsa.pem \
                  -subj "/CN=Jetson Orin fTPM EK RSA/O=Ghaf" \
                  -days 36500

                openssl ecparam -name prime256v1 -genkey -noout -out ek-ecc-key.pem
                openssl req -x509 -new -sha256 \
                  -key ek-ecc-key.pem -out ek-ecc.pem \
                  -subj "/CN=Jetson Orin fTPM EK ECC/O=Ghaf" \
                  -days 36500

                openssl x509 -in ek-rsa.pem -outform DER -out ek-rsa.der
                openssl x509 -in ek-ecc.pem -outform DER -out ek-ecc.der

        ${pkgs.buildPackages.nvidia-jetpack.genEkb}/bin/gen_ekb.py \
          -chip t234 \
          -oem_k1_key oem_k1.key \
          -in_auth_key auth.key \
          -in_ftpm_rsa_ek_cert ek-rsa.der \
          -in_ftpm_ec_ek_cert ek-ecc.der \
          -out "$out/eks_t234.img"
      '';

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

    runtimeEkProvision.enable = mkOption {
      description = "Provision EK certificates into TPM NV indices at runtime";
      type = types.bool;
      default = true;
    };

  };

  config = mkIf cfg.enable {
    hardware.nvidia-jetpack.firmware.eksFile = "${firmwareEkbImage}/eks_t234.img";
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

      # Prevent early autoload; load in stage-2 after local filesystems
      # and tee-supplicant are up.
      blacklistedKernelModules = [ "tpm_ftpm_tee" ];

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
        {
          name = "ftpm-config";
          patch = null;
          structuredExtraConfig = with lib.kernel; {
            EXPERT = yes;
            TCG_FTPM_TEE = module;
            # Disable TPM hwrng to prevent constant fTPM polling pressure
            # that can saturate the OP-TEE single-lane fTPM TA under load.
            HW_RANDOM_TPM = no;
          };
        }
      ];
    };

    services.udev.extraRules = ''
      SUBSYSTEM=="rtc", KERNEL=="rtc0", TEST=="${rtcSeedAnchorPath}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="ghaf-seed-time-from-rtc@%k.service"
    '';

    systemd.services."ghaf-seed-time-from-rtc@" = {
      description = "Seed system time from plausible RTC value (%I)";
      unitConfig = {
        ConditionPathExists = [
          "/sys/class/rtc/%I/since_epoch"
          rtcSeedAnchorPath
        ];
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = false;
        ExecStart = "${lib.getExe rtcSeedTimeFromRtc} %I";
      };
    };

    systemd.services.ghaf-load-ftpm-module = {
      description = "Load fTPM module after stage-2 OP-TEE readiness";
      wantedBy = [ "multi-user.target" ];
      wants = [
        "local-fs.target"
        "tee-supplicant.service"
      ];
      after = [
        "local-fs.target"
        "systemd-modules-load.service"
        "tee-supplicant.service"
      ];
      before = [
        "ghaf-provision-ek-certs.service"
        "ghaf-export-ek-endorsement-bundle.service"
      ];
      unitConfig.ConditionPathExists = "!/dev/tpmrm0";

      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "80s";
        ExecStart = lib.getExe loadFtpmModuleApp;
      };
    };

    systemd.services.ghaf-provision-ek-certs = mkIf cfg.runtimeEkProvision.enable {
      description = "Provision fTPM EK certificates into standard NV indices";
      wantedBy = [ "multi-user.target" ];
      wants = [ "tee-supplicant.service" ];
      after = [
        "local-fs.target"
        "systemd-modules-load.service"
        "dev-tpmrm0.device"
        "tee-supplicant.service"
        "ghaf-load-ftpm-module.service"
      ];
      requires = [ "dev-tpmrm0.device" ];
      unitConfig.ConditionPathExists = "/dev/tpmrm0";
      unitConfig.OnSuccess = [ "ghaf-export-ek-endorsement-bundle.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "90s";
        UMask = "0077";
        ExecStart = lib.getExe provisionEkCertsApp;
      };
    };

    systemd.services.ghaf-export-ek-endorsement-bundle = {
      description = "Export EK certs and build endorsement CA bundle";
      wantedBy = [ "multi-user.target" ];
      wants = [ "tee-supplicant.service" ];
      after = [
        "local-fs.target"
        "systemd-modules-load.service"
        "tee-supplicant.service"
        "ghaf-load-ftpm-module.service"
      ]
      ++ lib.optionals cfg.runtimeEkProvision.enable [
        "ghaf-provision-ek-certs.service"
      ];
      unitConfig.ConditionPathExists = "/dev/tpmrm0";

      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "45s";
        UMask = "0077";
        ExecStart = lib.getExe exportEkBundleApp;
      };
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
