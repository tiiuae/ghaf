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
# LVM payload: the image builder creates volume group "pool" with:
#   - root_<ver>_<hash>  (erofs nix-store image from ghafImage)
#   - verity_<ver>_<hash> (dm-verity hash tree from ghafImage)
#   - root_empty / verity_empty (reserved inactive system pair)
#
# Swap and persist LVs are created on first boot by
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
  buildPkgs = pkgs.pkgsBuildBuild;
  runVM = import ../../../../../lib/image-builder-vm.nix { pkgs = buildPkgs; };

  # The ghafUpdateImage derivation from verity-volume.nix produces:
  #   ghaf_root_<ver>_<hash>.raw.zst   — erofs nix-store image (compressed)
  #   ghaf_verity_<ver>_<hash>.raw.zst — dm-verity hash tree (compressed)
  #   ghaf_kernel_<ver>_<hash>.efi     — UKI with real roothash
  #   ghaf_<ver>_<hash>.manifest       — JSON manifest
  inherit (config.system.build) ghafUpdateImage;
  fixedSlotSizes = cfg.rootSlotSizeMiB != null && cfg.veritySlotSizeMiB != null;

  # The ESP is assembled at flash time because its EFI binaries need private
  # signing keys. The LVM/LUKS payload is created on a disposable build-VM disk
  # using stock cryptsetup and LVM tools.
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
    system.build.verityImages = runVM (
      buildPkgs.runCommand "verity-images"
        {
          preVM = ''
            mapfile -t manifests < <(find ${ghafUpdateImage} -maxdepth 1 -type f -name '*.manifest')
            [ "''${#manifests[@]}" -eq 1 ] || { echo "Expected exactly one update manifest" >&2; exit 1; }
            manifest="''${manifests[0]}"
            printf '%s' "$manifest" > xchg/manifest-path
            ${
              if fixedSlotSizes then
                ''
                  root_mib=${toString cfg.rootSlotSizeMiB}
                  verity_mib=${toString cfg.veritySlotSizeMiB}
                ''
              else
                ''
                  root_bytes=$(${buildPkgs.jq}/bin/jq -er '.root.unpacked_size' "$manifest")
                  verity_bytes=$(${buildPkgs.jq}/bin/jq -er '.verity.unpacked_size' "$manifest")
                  root_mib=$(( (root_bytes + 1048575) / 1048576 + 512 ))
                  verity_mib=$(( (verity_bytes + 1048575) / 1048576 + 16 ))
                ''
            }
            printf '%s\n' "$root_mib" > xchg/root_size_mib
            printf '%s\n' "$verity_mib" > xchg/verity_size_mib
            diskImage=$PWD/system.img
            truncate -s "$(( (2 * (root_mib + verity_mib) + 64 + ${
              if config.ghaf.hardware.nvidia.orin.diskEncryption.enable then "32" else "0"
            }) * 1048576 ))" "$diskImage"
          '';
          postVM = ''
            mkdir -p "$out"
            ln -s ${espFiles} "$out/esp-files"
            ln -s ${ghafUpdateImage} "$out/update"
            cp xchg/root_size_mib xchg/verity_size_mib "$out/"
            stat -c%s "$diskImage" > "$out/system.raw_size"
            ${lib.getExe buildPkgs.zstd} --compress --threads=0 "$diskImage" -o "$out/system.img.zst"
          '';
        }
        ''
          encryption=()
          ${lib.optionalString config.ghaf.hardware.nvidia.orin.diskEncryption.enable ''
            umask 077
            printf '%s' ${lib.escapeShellArg config.ghaf.hardware.nvidia.orin.diskEncryption.deviceUniqueKey.deviceManufacturerPassphrase} > manufacturer.key
            encryption=(--luks-uuid ${lib.escapeShellArg config.ghaf.hardware.nvidia.orin.diskEncryption.luksUuid} --key-file manufacturer.key)
          ''}
          ${lib.getExe buildPkgs.ghaf-initialize-verity-lvm} \
            --image /dev/vda --manifest "$(cat manifest-path)" --create-inactive-slots \
            --root-size-mib "$(cat root_size_mib)" --verity-size-mib "$(cat verity_size_mib)" \
            "''${encryption[@]}"
          rm -f manufacturer.key
        ''
    );

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
