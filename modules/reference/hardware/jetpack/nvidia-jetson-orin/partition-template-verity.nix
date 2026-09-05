# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Partition template for A/B verity boot on NVIDIA Jetson Orin.
#
# Produces a flash.xml with two partitions on the target storage device:
#   - ESP (512M, vfat) with systemd-boot + UKI
#   - APP (LVM PV) with A/B root+verity slots, swap, persist
#
# preFlashCommands copies pre-built images from verity-image.nix into the
# flash workdir and patches flash.xml with actual paths and sizes.
#
{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.orin;
  trustDigests = cfg.secureboot.publicTrustDigests;
  expectedPkDigest = trustDigests."PK.crt" or "";
  expectedKekDigest = trustDigests."KEK.crt" or "";
  expectedDbDigest = trustDigests."db.crt" or "";
  expectedUpdateDigest = trustDigests."update.pub" or "";

  inherit (config.system.build) verityImages;

  # Root storage partition layout as structured Nix data.
  # Serialized to JSON and spliced into NVIDIA's flash XML by
  # splice-flash-xml.py, which replaces either the eMMC
  # <device type="sdmmc_user"> or NVMe <device type="nvme"> children.
  # This avoids fragile line-count splicing.
  #
  # All values are fully resolved at Nix build time (the APP partition size is
  # derived from the exported slot capacities via --set).
  partitionsStorage = [
    {
      name = "master_boot_record";
      type = "protective_master_boot_record";
      children = {
        allocation_policy = "sequential";
        filesystem_type = "basic";
        size = "512";
        file_system_attribute = "0";
        allocation_attribute = "8";
        percent_reserved = "0";
      };
    }
    {
      name = "primary_gpt";
      type = "primary_gpt";
      children = {
        allocation_policy = "sequential";
        filesystem_type = "basic";
        size = "19968";
        file_system_attribute = "0";
        allocation_attribute = "8";
        percent_reserved = "0";
      };
    }
    {
      name = "esp";
      type = "data";
      children = {
        allocation_policy = "sequential";
        filesystem_type = "basic";
        size = "536870912";
        file_system_attribute = "0";
        allocation_attribute = "0x8";
        percent_reserved = "0";
        filename = "esp.img";
        partition_type_guid = "C12A7328-F81F-11D2-BA4B-00A0C93EC93B";
        description = "EFI system partition with systemd-boot + UKI.";
      };
    }
    {
      name = "APP";
      type = "data";
      children = {
        allocation_policy = "sequential";
        filesystem_type = "basic";
        size = "0"; # overridden by --set from verityImages at build time
        file_system_attribute = "0";
        allocation_attribute = "0x8";
        align_boundary = "16384";
        percent_reserved = "0x808";
        unique_guid = "APPUUID";
        filename = "system.img";
        description = "Prebuilt LVM payload for A/B root and verity slots.";
      };
    }
    {
      name = "secondary_gpt";
      type = "secondary_gpt";
      children = {
        allocation_policy = "sequential";
        filesystem_type = "basic";
        size = "0xFFFFFFFFFFFFFFFF";
        file_system_attribute = "0";
        allocation_attribute = "8";
        percent_reserved = "0";
      };
    }
  ];

  # Build the final flash.xml by replacing the storage-device partitions
  # in NVIDIA's template with our layout using XML-aware splicing.
  #
  # Orin NX has no eMMC. Its p3768 devkit must use NVIDIA's NVMe template;
  # using the SDMMC template makes MB2 probe SDMMC instance 3, fail with
  # "Secondary storage init failed", and hang in Busy Spin before flashing.
  partitionTemplate =
    let
      inherit (pkgs.nvidia-jetpack) bspSrc;
      inherit (config.hardware.nvidia-jetpack) som;
      isIndustrial = som == "orin-agx-industrial";
      isNvme = som == "orin-nx";
      xmlFile =
        if isIndustrial then
          "${bspSrc}/bootloader/generic/cfg/flash_t234_qspi_sdmmc_industrial.xml"
        else if isNvme then
          "${bspSrc}/bootloader/generic/cfg/flash_t234_qspi_nvme.xml"
        else
          "${bspSrc}/bootloader/generic/cfg/flash_t234_qspi_sdmmc.xml";
    in
    pkgs.runCommand "flash-verity.xml"
      {
        nativeBuildInputs = [ pkgs.buildPackages.python3 ];
      }
      ''
        python3 ${./splice-flash-xml.py} \
          --device-type "${if isNvme then "nvme" else "sdmmc_user"}" \
          ${lib.optionalString cfg.flashScriptOverrides.onlyQSPI "--remove-device"} \
          --set "APP.size=$(cat ${verityImages}/system.raw_size)" \
          ${xmlFile} \
          ${pkgs.writeText "verity-storage.json" (builtins.toJSON partitionsStorage)} \
          "$out"
      '';

  # preFlashCommands: Copy pre-built images and patch flash.xml
  preFlashCommands = ''
    echo "============================================================"
    echo "Ghaf A/B verity flash script for NVIDIA Jetson"
    echo "============================================================"
    echo "Version: ${config.ghaf.version}"
    echo "SoM: ${config.hardware.nvidia-jetpack.som}"
    echo "Carrier board: ${config.hardware.nvidia-jetpack.carrierBoard}"
    echo "============================================================"
    echo ""

    if [ -z "''${GHAF_DEV_KEY_DIR:-}" ]; then
      echo "ERROR: GHAF_DEV_KEY_DIR is required for secure A/B canary flashes." >&2
      exit 1
    fi
    for _required in PK.crt KEK.crt db.crt db.key update.pub update.key; do
      if [ ! -s "$GHAF_DEV_KEY_DIR/$_required" ]; then
        echo "ERROR: missing $GHAF_DEV_KEY_DIR/$_required" >&2
        exit 1
      fi
    done

    _check_public_trust() {
      _trust_name="$1"
      _expected_digest="$2"
      _actual_digest=$("${pkgs.pkgsBuildBuild.coreutils}/bin/sha256sum" "$GHAF_DEV_KEY_DIR/$_trust_name")
      _actual_digest="''${_actual_digest%% *}"
      if [ -z "$_expected_digest" ] || [ "$_actual_digest" != "$_expected_digest" ]; then
        echo "ERROR: GHAF_DEV_KEY_DIR public trust does not match the trust embedded at image evaluation: $_trust_name" >&2
        echo "  Rebuild the flash script with this exact GHAF_DEV_KEY_DIR." >&2
        exit 1
      fi
    }
    _check_public_trust PK.crt ${lib.escapeShellArg expectedPkDigest}
    _check_public_trust KEK.crt ${lib.escapeShellArg expectedKekDigest}
    _check_public_trust db.crt ${lib.escapeShellArg expectedDbDigest}
    _check_public_trust update.pub ${lib.escapeShellArg expectedUpdateDigest}

    _trust_check_dir=$(mktemp -d)
    "${pkgs.pkgsBuildBuild.openssl}/bin/openssl" pkey \
      -in "$GHAF_DEV_KEY_DIR/db.key" -pubout -outform DER \
      -out "$_trust_check_dir/db-key.der"
    "${pkgs.pkgsBuildBuild.openssl}/bin/openssl" x509 \
      -in "$GHAF_DEV_KEY_DIR/db.crt" -pubkey -noout \
      -out "$_trust_check_dir/db-cert.pem"
    "${pkgs.pkgsBuildBuild.openssl}/bin/openssl" pkey \
      -pubin -in "$_trust_check_dir/db-cert.pem" -outform DER \
      -out "$_trust_check_dir/db-cert.der"
    if ! "${pkgs.pkgsBuildBuild.diffutils}/bin/cmp" -s \
      "$_trust_check_dir/db-key.der" "$_trust_check_dir/db-cert.der"; then
      echo "ERROR: GHAF_DEV_KEY_DIR private key does not match public trust: db.key/db.crt" >&2
      exit 1
    fi

    "${pkgs.pkgsBuildBuild.openssl}/bin/openssl" pkey \
      -in "$GHAF_DEV_KEY_DIR/update.key" -pubout -outform DER \
      -out "$_trust_check_dir/update-key.der"
    "${pkgs.pkgsBuildBuild.coreutils}/bin/tail" -c 32 \
      "$_trust_check_dir/update-key.der" > "$_trust_check_dir/update-key.raw"
    if [ "$("${pkgs.pkgsBuildBuild.coreutils}/bin/wc" -c < "$GHAF_DEV_KEY_DIR/update.pub")" -ne 32 ] \
      || ! "${pkgs.pkgsBuildBuild.diffutils}/bin/cmp" -s \
        "$_trust_check_dir/update-key.raw" "$GHAF_DEV_KEY_DIR/update.pub"; then
      echo "ERROR: GHAF_DEV_KEY_DIR private key does not match public trust: update.key/update.pub" >&2
      exit 1
    fi
    rm -rf "$_trust_check_dir"

    mkdir -pv "$WORKDIR/bootloader"

    # jetpack-nixos sets NO_ESP_IMG=1; override so flash.sh assigns
    # localespfile=esp.img (needed for -k esp). The -r flag already
    # prevents flash.sh from rebuilding esp.img via create_espimage.
    export NO_ESP_IMG=0

    echo "Building ESP image..."
    _esp="$WORKDIR/bootloader/esp.img"
    _uki_name=$(cat "${verityImages}/esp-files/uki-filename")
    _uki_src="${verityImages}/esp-files/uki.efi"
    _boot_src="${verityImages}/esp-files/systemd-bootaa64.efi"

    # Copy to writable tmp so we can sign in-place
    _sign_dir=$(mktemp -d)
    cp "$_boot_src" "$_sign_dir/BOOTAA64.efi"
    cp "$_uki_src" "$_sign_dir/$_uki_name"

    # Sign EFI binaries if secure boot keys are available
    _sb_key_dir="$GHAF_DEV_KEY_DIR"
    if [ -n "$_sb_key_dir" ] && [ -f "$_sb_key_dir/db.key" ] && [ -f "$_sb_key_dir/db.crt" ]; then
      echo "Signing EFI binaries with $_sb_key_dir/db.crt ..."
      for _efi in "$_sign_dir"/*.efi; do
        echo "  Signing: $(basename "$_efi")"
        "${pkgs.pkgsBuildBuild.sbsigntool}/bin/sbsign" \
          --key "$_sb_key_dir/db.key" --cert "$_sb_key_dir/db.crt" \
          --output "$_efi" "$_efi"
      done
    ${
      if config.ghaf.hardware.nvidia.orin.secureboot.enable then
        ''
          else
            echo "ERROR: Secure Boot is enabled but no signing keys found." >&2
            echo "  Set GHAF_DEV_KEY_DIR to a directory from ghaf-dev-keygen." >&2
            exit 1
        ''
      else
        ''
          else
            echo "Secure Boot signing skipped (no keys found)."
        ''
    }
    fi

    # Create 512M FAT32 ESP image
    "${pkgs.pkgsBuildBuild.dosfstools}/bin/mkfs.vfat" -F 32 -n ESP -C "$_esp" $((512 * 1024))
    "${pkgs.pkgsBuildBuild.mtools}/bin/mmd" -i "$_esp" ::EFI
    "${pkgs.pkgsBuildBuild.mtools}/bin/mmd" -i "$_esp" ::EFI/BOOT
    "${pkgs.pkgsBuildBuild.mtools}/bin/mmd" -i "$_esp" ::EFI/Linux
    "${pkgs.pkgsBuildBuild.mtools}/bin/mcopy" -i "$_esp" "$_sign_dir/BOOTAA64.efi" ::EFI/BOOT/BOOTAA64.efi
    "${pkgs.pkgsBuildBuild.mtools}/bin/mcopy" -i "$_esp" "$_sign_dir/$_uki_name" "::EFI/Linux/$_uki_name"
    rm -rf "$_sign_dir"
    echo "ESP image built: $_esp"

    echo "Installing prebuilt LVM payload..."
    _outer="$WORKDIR/bootloader/system.img"
    "${lib.getExe pkgs.pkgsBuildBuild.zstd}" --decompress --force \
      "${verityImages}/system.img.zst" -o "$_outer"
    ${lib.optionalString config.ghaf.hardware.nvidia.orin.diskEncryption.enable ''
      _recovery_dir="$GHAF_DEV_KEY_DIR/recovery-passphrases"
      mkdir -p "$_recovery_dir"
      _recovery="$_recovery_dir/recovery-$(date -u +%Y%m%dT%H%M%SZ).txt"
      # Store exactly the printable passphrase bytes that an operator types.
      # A trailing newline would become part of a cryptsetup key file during
      # enrollment and make the printed value fail interactive recovery.
      "${pkgs.pkgsBuildBuild.openssl}/bin/openssl" rand -base64 24 \
        | "${pkgs.pkgsBuildBuild.coreutils}/bin/tr" -d '\n' > "$_recovery"
      chmod 0600 "$_recovery"

      printf '%s' ${lib.escapeShellArg config.ghaf.hardware.nvidia.orin.diskEncryption.deviceUniqueKey.deviceManufacturerPassphrase} \
        | "${pkgs.pkgsBuildBuild.cryptsetup}/bin/cryptsetup" luksAddKey \
          --new-key-slot 1 \
          --key-file=- "$_outer" "$_recovery"
      echo "============================================================"
      echo "RECOVERY PASSPHRASE (store securely; generated for this flash):"
      cat "$_recovery"
      printf '\n'
      echo "Saved at: $_recovery"
      echo "============================================================"
    ''}
    # flash.sh -k APP looks for system.img relative to $WORKDIR
    ln -sf "$WORKDIR/bootloader/system.img" "$WORKDIR/system.img"
    echo "APP image: $("${pkgs.pkgsBuildBuild.coreutils}/bin/stat" -c%s "$WORKDIR/bootloader/system.img") bytes"

    # Ensure all DTB variants in kernel/dtb/ have NixOS overlays applied.
    # NixOS only applies deviceTree.overlays to the DTB named in
    # hardware.deviceTree.name, but flash.sh picks a variant based on
    # the board's EEPROM SKU (e.g. p3701-0005 instead of p3701-0000).
    # Derive a glob from the configured DTB name by replacing the SOM
    # revision with a wildcard, then copy the composed DTB over all
    # matching variants so the overlay (notably PCI passthrough
    # iommus=<> fix) is always present in the firmware DTB.
    #
    # Example: tegra234-p3737-0000+p3701-0000-nv.dtb
    #        → tegra234-p3737-0000+p3701-*-nv.dtb
    echo "Copying composed DTB over all SOM variant DTBs..."
    chmod -R u+w kernel/dtb/
    composed="kernel/dtb/${config.hardware.deviceTree.name}"
    # Replace the last 4-digit revision before -nv.dtb with a wildcard
    dtb_glob="kernel/dtb/$(echo "${config.hardware.deviceTree.name}" | "${pkgs.pkgsBuildBuild.gnused}/bin/sed" 's/-[0-9]\{4\}-nv\.dtb$/-*-nv.dtb/')"
    for variant in $dtb_glob; do
      if [ "$variant" != "$composed" ]; then
        echo "  $composed -> $(basename "$variant")"
        cp "$composed" "$variant"
      fi
    done

    echo ""
    echo "Ready to flash!"
    echo "============================================================"
  '';
in
{
  config = lib.mkIf (cfg.enable && config.ghaf.partitioning.verity.enable) {
    hardware.nvidia-jetpack.flashScriptOverrides.partitionTemplate = partitionTemplate;
    hardware.nvidia-jetpack.flashScriptOverrides.preFlashCommands = preFlashCommands;
  };
}
