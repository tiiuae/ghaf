# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Partition template for A/B verity boot on NVIDIA Jetson Orin AGX.
#
# Produces a flash.xml with two partitions on eMMC:
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

  inherit (config.system.build) verityImages;

  # Partition XML with placeholders (substituted at flash time by preFlashCommands)
  partitionsEmmc = pkgs.writeText "sdmmc-verity.xml" ''
    <partition name="master_boot_record" type="protective_master_boot_record">
      <allocation_policy> sequential </allocation_policy>
      <filesystem_type> basic </filesystem_type>
      <size> 512 </size>
      <file_system_attribute> 0 </file_system_attribute>
      <allocation_attribute> 8 </allocation_attribute>
      <percent_reserved> 0 </percent_reserved>
    </partition>
    <partition name="primary_gpt" type="primary_gpt">
      <allocation_policy> sequential </allocation_policy>
      <filesystem_type> basic </filesystem_type>
      <size> 19968 </size>
      <file_system_attribute> 0 </file_system_attribute>
      <allocation_attribute> 8 </allocation_attribute>
      <percent_reserved> 0 </percent_reserved>
    </partition>
    <partition name="esp" type="data">
      <allocation_policy> sequential </allocation_policy>
      <filesystem_type> basic </filesystem_type>
      <size> 536870912 </size>
      <file_system_attribute> 0 </file_system_attribute>
      <allocation_attribute> 0x8 </allocation_attribute>
      <percent_reserved> 0 </percent_reserved>
      <filename> ESP_IMG_PATH </filename>
      <partition_type_guid> C12A7328-F81F-11D2-BA4B-00A0C93EC93B </partition_type_guid>
      <description> EFI system partition with systemd-boot + UKI. </description>
    </partition>
    <partition name="APP" type="data">
      <allocation_policy> sequential </allocation_policy>
      <filesystem_type> basic </filesystem_type>
      <size> LVM_SIZE </size>
      <file_system_attribute> 0 </file_system_attribute>
      <allocation_attribute> 0x8 </allocation_attribute>
      <align_boundary> 16384 </align_boundary>
      <percent_reserved> 0x808 </percent_reserved>
      <unique_guid> APPUUID </unique_guid>
      <filename> LVM_IMG_PATH </filename>
      <description> LVM PV containing A/B root+verity slots, swap, persist. </description>
    </partition>
    <partition name="secondary_gpt" type="secondary_gpt">
      <allocation_policy> sequential </allocation_policy>
      <filesystem_type> basic </filesystem_type>
      <size> 0xFFFFFFFFFFFFFFFF </size>
      <file_system_attribute> 0 </file_system_attribute>
      <allocation_attribute> 8 </allocation_attribute>
      <percent_reserved> 0 </percent_reserved>
    </partition>
  '';

  # Line counts for replacing the sdmmc_user device section in NVIDIA's flash XML.
  # These numbers specify where to splice our custom partition layout.
  #
  # WARNING: When updating jetpack-nixos/BSP version, verify these line counts
  # still match the <device type="sdmmc_user"> section boundaries in:
  # - flash_t234_qspi_sdmmc.xml (standard)
  # - flash_t234_qspi_sdmmc_industrial.xml (industrial variant)
  partitionTemplateReplaceRange =
    if (config.hardware.nvidia-jetpack.som == "orin-agx-industrial") then
      {
        firstLineCount = 631;
        lastLineCount = 2;
      }
    else
      {
        firstLineCount = 618;
        lastLineCount = 2;
      };

  # Build the final flash.xml by splicing our partition layout into NVIDIA's template
  partitionTemplate =
    let
      inherit (pkgs.nvidia-jetpack) bspSrc;
      isIndustrial = config.hardware.nvidia-jetpack.som == "orin-agx-industrial";
      xmlFile =
        if isIndustrial then
          "${bspSrc}/bootloader/generic/cfg/flash_t234_qspi_sdmmc_industrial.xml"
        else
          "${bspSrc}/bootloader/generic/cfg/flash_t234_qspi_sdmmc.xml";
    in
    pkgs.runCommand "flash-verity.xml" { } ''
      head -n ${toString partitionTemplateReplaceRange.firstLineCount} ${xmlFile} >"$out"
      cat ${partitionsEmmc} >>"$out"
      tail -n ${toString partitionTemplateReplaceRange.lastLineCount} ${xmlFile} >>"$out"
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
    _sb_key_dir="''${SECURE_BOOT_SIGNING_KEY_DIR:-${
      if config.ghaf.hardware.nvidia.orin.secureboot.enable then
        config.ghaf.hardware.nvidia.orin.secureboot.signingKeyDir
      else
        ""
    }}"
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
            echo "  Set SECURE_BOOT_SIGNING_KEY_DIR or place db.key + db.crt in:" >&2
            echo "  $_sb_key_dir" >&2
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

    echo "Decompressing pre-built system (LVM) sparse image..."
    "${pkgs.pkgsBuildBuild.zstd}/bin/zstd" -f -d "${verityImages}/system.img.zst" -o "$WORKDIR/bootloader/system.img"
    # flash.sh -k APP looks for system.img relative to $WORKDIR
    ln -sf "$WORKDIR/bootloader/system.img" "$WORKDIR/system.img"

    LVM_SIZE=$(cat "${verityImages}/system.raw_size")
    echo "LVM raw size: $LVM_SIZE bytes (sparse image: $("${pkgs.pkgsBuildBuild.coreutils}/bin/stat" -c%s "$WORKDIR/bootloader/system.img") bytes)"

    echo "Patching flash.xml with image paths and sizes..."
    "${pkgs.pkgsBuildBuild.gnused}/bin/sed" -i \
      -e "s#ESP_IMG_PATH#esp.img#" \
      -e "s#LVM_IMG_PATH#system.img#" \
      -e "s#LVM_SIZE#$LVM_SIZE#" \
      flash.xml

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
  config = lib.mkIf (cfg.enable && config.ghaf.partitioning.verity-volume.enable) {
    hardware.nvidia-jetpack.flashScriptOverrides.partitionTemplate = partitionTemplate;
    hardware.nvidia-jetpack.flashScriptOverrides.preFlashCommands = preFlashCommands;
  };
}
