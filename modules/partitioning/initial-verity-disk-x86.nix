# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# x86 bootstrap disk image for the shared secure A/B payload. GPT, FAT, LUKS,
# and LVM are assembled from regular files in the Nix build sandbox without a
# VM or kernel storage devices. The result is unsigned; ghaf-sign-x86-image
# signs its ESP later, outside the Nix store.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.partitioning.verity.initialDisk;
  verityCfg = config.ghaf.partitioning.verity;
  diskoCfg = config.ghaf.partitioning.disko;
  # ESP plus two fixed root/verity pairs, swap, persist, and conservative
  # headroom for GPT, LUKS, and LVM metadata.
  minimumImageSizeMiB =
    500
    + 2 * verityCfg.rootSlotSizeMiB
    + 2 * verityCfg.veritySlotSizeMiB
    + diskoCfg.swapSize
    + diskoCfg.persistSize
    + 4 * 1024;
  updateImage = config.system.build.ghafUpdateImage;
  trustInventory = pkgs.writeText "ghaf-secure-ab-public-trust.json" (
    builtins.toJSON {
      external = config.ghaf.secureUpdate.externalPublicTrustConfigured;
      inherit (config.ghaf.secureUpdate) target generation publicTrustDigests;
    }
  );
  buildPkgs = pkgs.pkgsBuildBuild;
  initialDiskImage = pkgs.runCommand "ghaf-x86-verity-disk" { } ''
    ${lib.getExe buildPkgs.ghaf-prepare-x86-verity-disk} \
      --update-dir ${updateImage} \
      --systemd-boot ${config.systemd.package}/lib/systemd/boot/efi/systemd-bootx64.efi \
      --trust-inventory ${trustInventory} \
      --image-size-mib ${toString diskoCfg.imageSize} \
      --root-size-mib ${toString verityCfg.rootSlotSizeMiB} \
      --verity-size-mib ${toString verityCfg.veritySlotSizeMiB} \
      --swap-size-mib ${toString diskoCfg.swapSize} \
      --persist-size-mib ${toString diskoCfg.persistSize} \
      --boot-timeout ${
        lib.escapeShellArg (
          if config.boot.loader.timeout == null then "menu-force" else toString config.boot.loader.timeout
        )
      } \
      --output "$out"
  '';
in
{
  options.ghaf.partitioning.verity.initialDisk.enable =
    lib.mkEnableOption "an initial x86 GPT/FAT/LUKS/LVM secure A/B disk image builder";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.nixpkgs.hostPlatform.system == "x86_64-linux";
        message = "ghaf.partitioning.verity.initialDisk is currently implemented only for x86_64-linux";
      }
      {
        assertion = config.ghaf.partitioning.verity.enable;
        message = "ghaf.partitioning.verity.initialDisk requires the verity update layout";
      }
      {
        assertion = config.ghaf.storage.encryption.enable && !config.ghaf.storage.encryption.deferred;
        message = "ghaf.partitioning.verity.initialDisk requires immediate LUKS configuration";
      }
      {
        assertion = diskoCfg.imageSize >= minimumImageSizeMiB;
        message = "secure A/B imageSize is ${toString diskoCfg.imageSize} MiB but two fixed system slots and persistent volumes require at least ${toString minimumImageSizeMiB} MiB";
      }
    ];

    ghaf.partitioning.disko.imageSize = lib.mkDefault minimumImageSizeMiB;

    fileSystems."/boot" = lib.mkForce {
      device = "/dev/disk/by-label/ESP";
      fsType = "vfat";
      options = [ "umask=0077" ];
    };

    boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
    system.build.ghafImage = lib.mkForce initialDiskImage;
  };
}
