# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Configuration for NVIDIA Jetson Orin AGX/NX reference boards
{
  lib,
  config,
  options,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.orin;

  # verity-volume.nix owns fileSystems."/" (tmpfs overlay) when enabled, so the
  # diskEncryption ext4 root override below must stand down to avoid a
  # conflicting mkForce. Defensive `options ?` check so this evaluates even in
  # module sets where the verity option is absent. An assertion below rejects
  # the combination outright.
  verityEnabled =
    (options ? ghaf.partitioning.verity.enable) && config.ghaf.partitioning.verity.enable;
  luksDiskKeyDescription = "luksDiskDeviceUniqueKey";
  inherit (cfg.diskEncryption) luksUuid;

  # ESP is referenced by its FAT label, which both media share. Fall back to the
  # sd-image default when config.sdImage is absent (e.g. verity image builds),
  # so this evaluates in module sets that do not use the sd-image format.
  espLabel = config.sdImage.firmwarePartitionName or "FIRMWARE";
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
      config.ghaf.security.tpm2.tools
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
      config.ghaf.security.tpm2.tools
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

        # Used for disk encryption.
        printf '%s' "0x00000000000000000000000000000000" > sym2_t234.key

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
          -in_sym_key2 sym2_t234.key \
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

  resizepartitionsScript = pkgs.writeShellApplication {
    name = "resize-partitions-cmds";
    runtimeInputs = with pkgs; [
      gptfdisk
      parted
      cryptsetup
      util-linux
      e2fsprogs
      coreutils
      systemd
    ];
    text = ''
      RESIZE_MARKER=".ghaf-resize-done"
      ESP_MOUNT="/mnt-esp"
      ESP_DEVICE="/dev/disk/by-label/${espLabel}"

      # Resolve the root partition by the pinned LUKS header UUID rather than a
      # hardcoded device name or a partition-table PARTUUID (which differs between
      # the USB sd-image (MBR) and the eMMC/NVMe flash (GPT)). blkid matches the
      # crypto_LUKS container by its own UUID, identical on both media.
      PART_DEV=""
      for _ in $(seq 1 30); do
        for d in $(blkid -o device -t UUID=${luksUuid} 2>/dev/null); do
          ${lib.optionalString cfg.diskEncryption.enable ''
            [ "$(blkid -o value -s TYPE "$d" 2>/dev/null)" = "crypto_LUKS" ] || continue
          ''}
          PART_DEV="$d"
          break
        done
        if [ -n "$PART_DEV" ]; then break; fi
        sleep 1
      done

      if [ -z "$PART_DEV" ]; then
        echo "Root partition (LUKS UUID=${luksUuid}) not found, skipping resize."
        exit 0
      fi

      # Derive disk and partition number from the resolved node, so mmcblk/nvme/sda all work.
      real_dev=$(readlink -f "$PART_DEV")
      base_dev=$(basename "$real_dev")
      PART_NUM=$(cat "/sys/class/block/$base_dev/partition")
      DISK="/dev/$(basename "$(readlink -f "/sys/class/block/$base_dev/..")")"

      RESIZE_TARGET="$PART_DEV"
      ${lib.optionalString cfg.diskEncryption.enable ''
        MAPPER_NAME="${cfg.diskEncryption.mapperName}"
        RESIZE_TARGET="/dev/mapper/$MAPPER_NAME"
      ''}

      mkdir -p "$ESP_MOUNT"
      if [[ -b $ESP_DEVICE ]]; then
        if mount "$ESP_DEVICE" "$ESP_MOUNT"; then
          if [ -f "$ESP_MOUNT/$RESIZE_MARKER" ]; then
            echo "Resize already performed, skipping."
            umount "$ESP_MOUNT"
            exit 0
          fi
          umount "$ESP_MOUNT"
        else
          echo "Failed to mount ESP $ESP_DEVICE, continuing without marker check."
        fi
      else
        echo "ESP partition not found, continuing without marker check."
      fi

      for _ in {1..30}; do
        [ -b "$RESIZE_TARGET" ] && break
        sleep 1
      done

      if [ ! -b "$RESIZE_TARGET" ]; then
        echo "Target device $RESIZE_TARGET not found, skipping."
        exit 0
      fi

      echo "Fixing GPT..."
      sgdisk -e "$DISK" || true

      echo "Resizing partition $PART_NUM to 100%..."
      # Use resizepart which works on busy partitions by using the BLKPG_RESIZE_PARTITION ioctl
      parted -s "$DISK" resizepart "$PART_NUM" 100%

      partprobe "$DISK" || true
      udevadm settle || true

      ${lib.optionalString cfg.diskEncryption.enable ''
        echo "Resizing LUKS container $MAPPER_NAME..."
        ${
          # deviceUniqueKey and userPassphrase are mutually exclusive and exactly
          # one is set (assertion below), so this if/else always resizes.
          if cfg.diskEncryption.deviceUniqueKey.enable then
            ''
              cryptsetup resize --key-description ${luksDiskKeyDescription} "$MAPPER_NAME"
            ''
          else
            ''
              # Use systemd-ask-password to handle prompts in a non-interactive environment
              PASSPHRASE=$(systemd-ask-password --timeout=60 "Enter passphrase for resizing LUKS container:")
              if [ -n "$PASSPHRASE" ]; then
                echo "$PASSPHRASE" | cryptsetup resize -v "$MAPPER_NAME" --key-file=-
              else
                echo "No passphrase entered, LUKS resize might have failed."
              fi
            ''
        }
        echo "LUKS status for $MAPPER_NAME after resize:"
        cryptsetup status "$MAPPER_NAME"
      ''}

      echo "Resizing filesystem on $RESIZE_TARGET..."
      # resize2fs may require a filesystem check before resizing
      e2fsck -fy "$RESIZE_TARGET" || true
      resize2fs "$RESIZE_TARGET"

      # Persist completion on the ESP so later initrd boots can skip the
      # service without mounting the root filesystem and racing fsck.
      if [[ -b $ESP_DEVICE ]] && mount "$ESP_DEVICE" "$ESP_MOUNT"; then
        touch "$ESP_MOUNT/$RESIZE_MARKER"
        umount "$ESP_MOUNT"
      else
        echo "Failed to persist resize marker on ESP."
      fi
    '';
  };

  preDiskUniqueKeyScript = pkgs.writeShellApplication {
    name = "pre-disk-unique-key";
    runtimeInputs = with pkgs; [
      cryptsetup
      coreutils
      gnused
      keyutils
      nvidia-jetpack.nvLuksSrv
      gnugrep
      util-linux
    ];
    text = ''
      handle_error() {
        if ! nvluks-srv-app -n; then
          printf "Note: Attempt to stop the nvluks service failed (it may have already been stopped). Proceeding with device reboot.\n"
        fi

        printf "Encountered unexpected/unrecoverable error with disk encryption.\n"
        printf "Rebooting in 10 seconds...\n"
        sleep 10
        reboot
      }

      wait_for_luks_device() {
        luksDev=$1

        for _ in {0..5}; do
          if cryptsetup isLuks "$luksDev"; then
            return 0
          fi
          sleep 1
        done

        printf "error: [%s] is not a luks device OR device is not ready\n" "$luksDev"
        handle_error
      }

      sanitize_string() {
        local dirty_str="$1"

        echo "$dirty_str" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9'
      }

      read_luksDev_serial() {
        local luksDev=$1
        local luksSerial

        luksSerial=$(sanitize_string "$(udevadm info --query=property --name="$luksDev" | sed -n 's/^ID_SERIAL=//p')")
        if [[ -z "$luksSerial" ]]; then
           printf "error: Failed to get luksDev serial\n"
           handle_error
        else
          echo "$luksSerial"
        fi
      }

      switch_to_use_device_unique_key() {
        uniqueKeyDescription=$1
        defaultKey=$2
        luksDev=$3

        printf "Switching to use device unique key. This might take a bit..\n"
        if ! printf "%s" "$defaultKey" | cryptsetup luksAddKey --new-key-description "$uniqueKeyDescription" --key-file=- "$luksDev"; then
          printf "error: Failed to set unique key\n"
          handle_error
        fi

        if ! printf "%s" "$defaultKey" | cryptsetup luksRemoveKey --key-file=- "$luksDev"; then
          printf "error: Failed to remove default key\n"
          handle_error
        fi

        # luksAddKey/luksRemoveKey only swap keyslots; the volume key that
        # actually encrypts the data is still the one the manufacturing
        # passphrase protected. Reencrypt derives a fresh volume key from the
        # device-unique key, so a leaked manufacturing passphrase grants nothing.
        printf "Note: Re-encryption may take 1 minute for every 1 GB of data ...\n"
        if ! cryptsetup reencrypt --key-description "$uniqueKeyDescription" "$luksDev"; then
           printf "error: Re-encryption failed\n"
           handle_error
        fi
      }

      # Resolve the LUKS partition by its pinned header UUID and verify it is a
      # crypto_LUKS payload, independent of mmcblk/nvme/sda enumeration and of the
      # partition-table scheme (MBR on USB, GPT on eMMC/NVMe).
      luksDev=""
      for _ in $(seq 1 30); do
        for d in $(blkid -o device -t UUID=${luksUuid} 2>/dev/null); do
          [ "$(blkid -o value -s TYPE "$d" 2>/dev/null)" = "crypto_LUKS" ] || continue
          luksDev="$d"
          break
        done
        if [ -n "$luksDev" ]; then break; fi
        sleep 1
      done
      if [[ -z "$luksDev" ]]; then
        printf "error: LUKS root partition (UUID=%s) not found\n" "${luksUuid}"
        handle_error
      fi
      defaultManufactureKey=${cfg.diskEncryption.deviceUniqueKey.deviceManufacturerPassphrase}
      luksDiskKeyKeyringDescription=${luksDiskKeyDescription}

      wait_for_luks_device "$luksDev"

      luksDevSerial=$(read_luksDev_serial "$luksDev")

      luksKeyKeyringID=$(printf "%s" "$(nvluks-srv-app -c "$luksDevSerial" -u | tr -d '\n')" | keyctl padd user "$luksDiskKeyKeyringDescription" @u)

      # Lock/prevent any other queries to luks key
      if ! nvluks-srv-app -n; then
        printf "error: Unable to stop nvluks service\n";
        handle_error
      fi

      # Granting write access, because otherwise key is not removable
      if ! keyctl setperm "$luksKeyKeyringID"  0x3f070000; then
        printf "error: Unable modify setperm\n"
        handle_error
      fi

      if ! keyctl describe "$luksKeyKeyringID" > /dev/null 2>&1; then
        printf "error: Unable to add luks key to keyring\n"
        handle_error
      fi


      # First boot is determined by checking whether the LUKS keyring description exists.
      # Do not use cryptsetup --test-passphrase for this check, because it succeeds
      # if the device can be unlocked by any available mechanism, including tokens/keyring.
      if ! cryptsetup luksDump "$luksDev" 2>/dev/null | grep -Fq ${luksDiskKeyDescription}; then
        switch_to_use_device_unique_key "$luksDiskKeyKeyringDescription" "$defaultManufactureKey" "$luksDev"
      fi

      if ! cryptsetup token add --key-description "$luksDiskKeyKeyringDescription" "$luksDev" > /dev/null 2>&1; then
        printf "error: Unable to add cryptrsetup token\n"
        handle_error
      fi
    '';
  };

  postDiskUniqueKeyScript = pkgs.writeShellApplication {
    name = "post-disk-unique-key";
    runtimeInputs = with pkgs; [
      coreutils
      keyutils
    ];
    text = ''
      if ! keyctl revoke "$(keyctl search @u user ${luksDiskKeyDescription})"; then
        printf "warn: Unable to revoke a key from keyring\n"
      fi
    '';
  };

  # Shared by the deviceDisk, deviceDiskRootfsPartition and deviceDiskEspPartition
  # options declared below.
  deviceDiskDescription = ''
    Rootfs disk and its ESP/rootfs partitions, as kernel device names. The
    rootfs partition is passed to NVIDIA's flash.sh as the trailing argument
    and is consumed by the partition layout in the .conf file referenced by
    configFileName, deciding where the APP partition lands. Downstream callers
    (e.g. disk-encryption modules) read these to know the rootfs location at
    build time.

    Orin NX booting from USB, for example:

    ```nix
    flashScriptOverrides.deviceDisk = "sda";
    flashScriptOverrides.deviceDiskEspPartition = "sda1";
    flashScriptOverrides.deviceDiskRootfsPartition = "sda2";
    ```

    No default: rootfs storage is not common to all carrier boards, so every
    per-SoM module must set all three explicitly. An assertion in the config
    block enforces non-empty values.
  '';

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

    flashScriptOverrides.deviceDisk = mkOption {
      description = deviceDiskDescription;
      type = types.str;
      default = "";
    };

    flashScriptOverrides.deviceDiskRootfsPartition = mkOption {
      description = deviceDiskDescription;
      type = types.str;
      default = "";
    };

    flashScriptOverrides.deviceDiskEspPartition = mkOption {
      description = deviceDiskDescription;
      type = types.str;
      default = "";
    };

    flashScriptOverrides.signedArtifactsPath = mkOption {
      description = ''
        Absolute path on the host that contains pre-signed Jetson Orin boot
        artifacts.

        The flash script expects at least `BOOTAA64.EFI` and `Image` to be
        present in this directory. Optional files such as `initrd` or device
        trees can be staged as well. The directory can also be provided at
        runtime through the `SIGNED_ARTIFACTS_DIR` environment variable.
      '';
      type = types.nullOr types.str;
      default = null;
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

    diskEncryption = {
      enable = mkEnableOption "generic LUKS root filesystem encryption for eMMC APP partition";

      deviceUniqueKey = {
        enable = mkEnableOption ''
          disk decryption using a unique hardware key fetched from the OP-TEE.

          On the first boot, the key (initially encrypted with a manufacturer key)
          is rotated and re-encrypted with a device-unique key. Note that this
          initial setup makes the first boot significantly slower.

          This method provides an unattended boot process and does not require
          user input to unlock the drive'';

        deviceManufacturerPassphrase = mkOption {
          description = ''
            The temporary passphrase used to decrypt the device disk at the first
            boot. Once the key is rotated to a device-unique key, this passphrase
            is no longer needed for subsequent unlocks.
          '';
          type = types.str;
          default = "ghaf";
        };
      };

      userPassphrase = {
        enable = mkEnableOption ''
          a semi-manual passphrase for disk encryption. During device boot, the
          device will prompt the console for the user to input the password.

          Note: This option is primarily intended for testing purposes'';

        passphrase = mkOption {
          description = "The manual passphrase used to encrypt the disk.";
          type = types.str;
          default = "ghaf";
        };
      };

      mode = mkOption {
        description = "Disk encryption mode for Jetson root filesystem";
        type = types.enum [ "generic-luks-passphrase" ];
        default = "generic-luks-passphrase";
      };

      mapperName = mkOption {
        description = "Mapped device name used by initrd after LUKS unlock";
        type = types.str;
        default = "cryptroot";
      };

      luksUuid = mkOption {
        description = ''
          Pinned LUKS2 header UUID of the encrypted root. Set on the container at
          image build time (`sdimage.nix`, `cryptsetup reencrypt --uuid`) and
          referenced at runtime as `/dev/disk/by-uuid/<uuid>` by the crypttab
          device, the `pre-disk-unique-key` udev rule and the resize scan.

          The header UUID rather than a partition PARTUUID, because the same
          container ships on two partition tables — the raw sd-image on USB
          (MBR) and the NVIDIA flash on eMMC/NVMe (GPT) — which necessarily carry
          different PARTUUIDs. The header lives inside the container, so it is
          identical on both media and independent of the kernel device name
          (mmcblk/nvme/sda). It also survives the first-boot device-unique-key
          rekey, which is a keyslot operation, not a header rewrite.

          Read-only: two drives holding a verbatim ghaf flash carry the same UUID,
          so a runtime scan cannot tell them apart and picks the first match.
          Disambiguating needs a per-install-unique UUID, left as follow-up.
        '';
        type = types.str;
        readOnly = true;
        default = "0ada0e5b-0e5b-4e5b-8e5b-0000000000a9";
      };
    };
  };

  config = mkIf cfg.enable {
    # jetpack ships 99-tegra-devices.rules which sets GROUP="debug" on Tegra
    # debug device nodes, but NixOS creates no `debug` group -> udev logs
    # "Failed to resolve group 'debug', ignoring" for every matching rule on
    # every device event (floods the journal >10/s under DRM device churn).
    # Define the group so udev resolves it and applies the intended ownership.
    users.groups.debug = { };

    assertions = [
      {
        assertion =
          cfg.flashScriptOverrides.deviceDisk != ""
          && cfg.flashScriptOverrides.deviceDiskRootfsPartition != ""
          && cfg.flashScriptOverrides.deviceDiskEspPartition != "";
        message = ''
          ghaf.hardware.nvidia.orin.flashScriptOverrides.deviceDisk* must be
          set explicitly (e.g. "mmcblk0" for eMMC/SD, "nvme0n1" for NVMe).
          The default is intentionally empty because rootfs storage varies per
          carrier board; the per-SoM module must declare it to avoid silently
          flashing to the wrong device.
        '';
      }
      {
        assertion =
          if cfg.diskEncryption.enable then
            (cfg.diskEncryption.deviceUniqueKey.enable != cfg.diskEncryption.userPassphrase.enable)
          else
            true;
        message = ''
          Disk encryption is enabled, but the unlock method is misconfigured.
          You must enable exactly one of:
          - 'diskEncryption.deviceUniqueKey.enable'
          - 'diskEncryption.userPassphrase.enable'

          Note: They are mutually exclusive and cannot both be false.
        '';
      }
      {
        assertion = !(cfg.diskEncryption.enable && verityEnabled);
        message = ''
          ghaf.hardware.nvidia.orin.diskEncryption.enable and
          ghaf.partitioning.verity.enable are mutually exclusive root strategies:
          verity owns fileSystems."/" as a tmpfs overlay, LUKS as an ext4 root on
          /dev/mapper/${cfg.diskEncryption.mapperName}. Enable at most one.
        '';
      }
    ];
    ghaf.hardware.nvidia.orin.secureboot.enable = lib.mkDefault (
      cfg.flashScriptOverrides.signedArtifactsPath != null
    );
    hardware.nvidia-jetpack.firmware.eksFile = "${firmwareEkbImage}/eks_t234.img";
    hardware.nvidia-jetpack.kernel.version = "${cfg.kernelVersion}";
    # jetpack-nixos hardcodes the trailing rootfs device as mmcblk0p1; replay
    # the same default here but route it through cfg.flashScriptOverrides.deviceDiskRootfsPartition
    # so per-SoM modules (e.g. orin-nx → nvme0n1p2) only set the option, not
    # the whole flashArgs list. mkOverride 75 beats jetpack-nixos's plain
    # assignment (prio 100) while leaving room for downstream mkForce (prio 50).
    hardware.nvidia-jetpack.flashScriptOverrides.flashArgs = lib.mkOverride 75 [
      config.hardware.nvidia-jetpack.flashScriptOverrides.configFileName
      cfg.flashScriptOverrides.deviceDiskRootfsPartition
    ];
    nixpkgs.hostPlatform.system = "aarch64-linux";

    ghaf.givc.enable = true;
    ghaf.givc.debug = false;
    ghaf.logging.enable = true;
    ghaf.logging.listener.address = config.ghaf.networking.hosts.admin-vm.ipv4;

    ghaf.global-config.givc.enable = true;
    ghaf.global-config.logging.enable = true;

    environment.systemPackages = with pkgs; [
      gptfdisk
      parted
      cryptsetup
      util-linux
      e2fsprogs
    ];

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
      ]
      ++ lib.optionals (cfg.diskEncryption.enable && cfg.kernelVersion == "upstream-6-6") [
        {
          name = "dm-crypt-config";
          patch = null;
          # LUKS needs the device-mapper stack built in (not modular) so the
          # initrd can open cryptroot. Force the DM entries to win over the
          # modular defaults the jetpack/verity kernel config pulls in (=m),
          # which otherwise collide on the -verity-*-luks combo targets.
          structuredExtraConfig = with lib.kernel; {
            BLK_DEV_DM = lib.mkForce yes;
            DM_BUFIO = lib.mkForce yes;
            DM_BIO_PRISON = lib.mkForce yes;
            DM_CRYPT = lib.mkForce yes;
            CRYPTO_USER_API = yes;
            CRYPTO_USER_API_HASH = yes;
            CRYPTO_USER_API_SKCIPHER = yes;
            CRYPTO_XTS = yes;
          };
        }
      ];

    };

    boot.initrd = {
      # Keep module selection aligned with the Orin JetPack baseline and avoid
      # requesting dm-crypt as a loadable module for upstream-6-6.
      availableKernelModules = [
        "xhci-tegra"
        "ucsi_ccg"
        "typec_ucsi"
        "typec"
        "nvme"
        "tegra_mce"
        "phy-tegra-xusb"
        "i2c-tegra"
        "fusb301"
        "phy_tegra194_p2u"
        "pcie_tegra194"
        "nvpps"
        "nvethernet"
      ]
      ++ lib.optionals cfg.diskEncryption.enable [
        "dm-crypt"
        "dm-mod"
      ];
      kernelModules = [ ];
      # algif_skcipher is not available with the upstream-6-6 kernel variant
      # used by current Orin reference targets.
      luks.cryptoModules = lib.mkIf cfg.diskEncryption.enable (
        lib.mkForce [
          "aes"
          "aes_generic"
          "cbc"
          "xts"
          "sha1"
          "sha256"
          "sha512"
          "af_alg"
        ]
      );
      luks.devices = lib.mkIf cfg.diskEncryption.enable {
        ${cfg.diskEncryption.mapperName} = {
          device = "/dev/disk/by-uuid/${luksUuid}";
          allowDiscards = true;
          keyFile = if cfg.diskEncryption.deviceUniqueKey.enable then "none" else null;
        };
      };

      systemd.initrdBin = with pkgs; [
        gnused
        keyutils
        nvidia-jetpack.nvLuksSrv
        gnugrep
      ];

      systemd.storePaths =
        with pkgs;
        [
          gptfdisk
          parted
          cryptsetup
          util-linux
          e2fsprogs
          coreutils
          systemd
          resizepartitionsScript
        ]
        ++ lib.optionals cfg.diskEncryption.deviceUniqueKey.enable [
          preDiskUniqueKeyScript
          postDiskUniqueKeyScript
        ];

      services.udev.rules = lib.optionalString cfg.diskEncryption.deviceUniqueKey.enable ''
        ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_UUID}=="${luksUuid}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="pre-disk-unique-key.service"
      '';

      systemd.services = {
        resize-partitions = {
          description = "Resize partitions to fill the disk on first boot";
          wantedBy = [ "initrd.target" ];
          before = [
            "systemd-fsck-root.service"
            "sysroot.mount"
            "initrd-root-fs.target"
          ];
          after = [
            "initrd-root-device.target"
            "cryptsetup.target"
          ];
          unitConfig = {
            DefaultDependencies = false;
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${resizepartitionsScript}/bin/resize-partitions-cmds";
            StandardInput = "tty";
            StandardOutput = "journal+console";
            StandardError = "journal+console";
            KeyringMode = "shared";
          };
        };
      }
      // lib.optionalAttrs cfg.diskEncryption.deviceUniqueKey.enable {
        load-diskkey-to-keyring = {
          description = "Service for loading unique device key to kernel keyring";
          before = [
            "systemd-pre-disk-unique-key.service"
          ];
          unitConfig = {
            DefaultDependencies = false;
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${preDiskUniqueKeyScript}/bin/pre-disk-unique-key";
            StandardInput = "tty";
            StandardOutput = "journal+console";
            StandardError = "journal+console";
          };
        };

        pre-disk-unique-key = {
          description = "Service for device unique key disk encryption";
          before = [
            "systemd-cryptsetup@${cfg.diskEncryption.mapperName}.service"
          ];
          unitConfig = {
            DefaultDependencies = false;
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${preDiskUniqueKeyScript}/bin/pre-disk-unique-key";
            StandardInput = "tty";
            StandardOutput = "journal+console";
            StandardError = "journal+console";
            KeyringMode = "shared";
          };
        };

        post-disk-unique-key = {
          description = "Cleanup service for device unique key disk encryption";
          wantedBy = [ "initrd-switch-root.target" ];
          after = [
            "systemd-resize-partitions.service"
          ];
          unitConfig = {
            DefaultDependencies = false;
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${postDiskUniqueKeyScript}/bin/post-disk-unique-key";
            StandardInput = "tty";
            StandardOutput = "journal+console";
            StandardError = "journal+console";
          };
        };
      };

      supportedFilesystems = [
        "ext4"
        "vfat"
      ];
    };

    fileSystems = mkIf (cfg.diskEncryption.enable && !verityEnabled) {
      "/" = lib.mkForce {
        device = "/dev/mapper/${cfg.diskEncryption.mapperName}";
        fsType = "ext4";
      };
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
        "tee-supplicant.service"
        "ghaf-load-ftpm-module.service"
      ];
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
