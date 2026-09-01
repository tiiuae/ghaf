# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Builds ESP and LVM partition images for A/B verity boot on Jetson Orin.
#
# ESP image: 512M vfat with systemd-boot + UKI (without .dtb section).
#            The UKI omits the .dtb because NVIDIA's EFI_DT_FIXUP_PROTOCOL
#            corrupts DTBs loaded from memory by sd-stub. Without .dtb,
#            sd-stub skips fixup and the kernel uses the firmware's DTB
#            already in the EFI Configuration Table (installed by DtPlatformDxe).
#
# LVM image: PV containing volume group "pool" with only the A-slot:
#   - root_<ver>_<hash>  (erofs nix-store image from ghafImage)
#   - verity_<ver>_<hash> (dm-verity hash tree from ghafImage)
#
# Swap, persist and B-slot LVs are created on first boot by
# firstboot-persist.nix, which resizes the APP partition to fill the
# eMMC and uses the free VG space.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.ghaf.partitioning.verity;

  # The ghafUpdateImage derivation from verity-volume.nix produces:
  #   ghaf_root_<ver>_<hash>.raw.zst   — erofs nix-store image (compressed)
  #   ghaf_verity_<ver>_<hash>.raw.zst — dm-verity hash tree (compressed)
  #   ghaf_kernel_<ver>_<hash>.efi     — UKI with real roothash
  #   ghaf_<ver>_<hash>.manifest       — JSON manifest
  inherit (config.system.build) ghafUpdateImage verityLvmImage;

  # The ESP FAT image is built at flash time (not here) so that
  # EFI binaries can be signed with a private key that never enters
  # the Nix store.  We only export the individual files needed.
  espFiles = pkgs.runCommand "esp-files" { } ''
    mkdir -p $out

    # UKI (roothash-patched)
    uki=$(find ${ghafUpdateImage} -name '*.efi' | head -1)
    if [ -z "$uki" ]; then
      echo "ERROR: No UKI (.efi) found in ghafImage output"
      ls -la ${ghafUpdateImage}/
      exit 1
    fi
    ln -s "$uki" "$out/uki.efi"

    # The image artifact keeps its manifest-facing ghaf_kernel_* name, but
    # systemd-boot and ota-update use ghaf-<version>-<hash>.efi as the stable
    # managed entry ID.  Flash the initial UKI under that same name so the
    # first slot participates in normal A/B discovery and is removed when its
    # physical slot is reused.
    manifest=$(find ${ghafUpdateImage} -name '*.manifest' | head -1)
    version=$(${pkgs.buildPackages.jq}/bin/jq -er '.version' "$manifest")
    root_hash=$(${pkgs.buildPackages.jq}/bin/jq -er '.root_verity_hash' "$manifest")
    printf 'ghaf-%s-%s.efi\n' "$version" "''${root_hash:0:16}" > "$out/uki-filename"

    # systemd-boot
    ln -s "${config.systemd.package}/lib/systemd/boot/efi/systemd-bootaa64.efi" \
      "$out/systemd-bootaa64.efi"
  '';

in
{
  config = lib.mkIf cfg.enable {
    system.build.verityImages = pkgs.runCommand "verity-images" { } ''
      mkdir -p $out
      ln -s ${espFiles} $out/esp-files
      ln -s ${verityLvmImage}/system.img.zst $out/system.img.zst
      # NVIDIA's flash-time outer LUKS container needs header headroom.
      lvm_size=$(cat ${verityLvmImage}/system.raw_size)
      echo $((lvm_size + 32 * 1024 * 1024)) > $out/system.raw_size
    '';

    # Configure filesystem mounts for the verity layout.
    # /persist and swap are declared in firstboot-persist.nix.
    fileSystems = {
      "/boot" = {
        device = "/dev/disk/by-label/ESP";
        fsType = "vfat";
        options = [ "umask=0077" ];
      };
    };

    # Disable systemd-boot-dtb and NixOS boot installer — ESP is built at image time.
    ghaf.hardware.aarch64.systemd-boot-dtb.enable = lib.mkForce false;
    boot.loader.systemd-boot.enable = lib.mkForce false;
    boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

    # Build UKI WITHOUT .dtb section. NVIDIA's EFI_DT_FIXUP_PROTOCOL corrupts
    # DTBs loaded from memory by sd-stub. Without .dtb, sd-stub skips fixup
    # and the kernel uses the firmware's DTB from the EFI Configuration Table
    # (installed by DtPlatformDxe during UEFI boot).
    #
    # NixOS adds DeviceTree to boot.uki.settings.UKI when
    # hardware.deviceTree is enabled. We can't disable hardware.deviceTree
    # (the flash tooling needs it for DTB overlays), so we override the
    # entire UKI section to omit DeviceTree while keeping all other
    # settings at their NixOS defaults.
    boot.uki.settings.UKI = lib.mkForce {
      Linux = "${config.boot.kernelPackages.kernel}/${config.system.boot.loader.kernelFile}";
      Initrd = "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}";
      Cmdline = "init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams}";
      Stub = "${pkgs.systemd}/lib/systemd/boot/efi/linux${pkgs.stdenv.hostPlatform.efiArch}.efi.stub";
      Uname = config.boot.kernelPackages.kernel.modDirVersion;
      OSRelease = "@${config.system.build.etc}/etc/os-release";
      EFIArch = pkgs.stdenv.hostPlatform.efiArch;
    };
  };
}
