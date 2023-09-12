# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Function to generate split images from nixos-disk-image
{
  pkgs,
  src,
  ...
}:
pkgs.stdenvNoCC.mkDerivation {
  inherit src;
  name = "split-images";
  nativeBuildInputs = [pkgs.util-linux pkgs.zstd];
  installPhase = ''
    img="./nixos.img"
    fdisk_output=$(fdisk -l "$img")

    # Offsets and sizes are in 512 byte sectors
    blocksize=512

    # ESP partition offset and sector count
    part_esp=$(echo -n "$fdisk_output" | tail -n 2 | head -n 1 | tr -s ' ')
    part_esp_begin=$(echo -n "$part_esp" | cut -d ' ' -f2)
    part_esp_count=$(echo -n "$part_esp" | cut -d ' ' -f4)

    # root-partition offset and sector count
    part_root=$(echo -n "$fdisk_output" | tail -n 1 | head -n 1 | tr -s ' ')
    part_root_begin=$(echo -n "$part_root" | cut -d ' ' -f2)
    part_root_count=$(echo -n "$part_root" | cut -d ' ' -f4)

    # Extract partitions to separate files
    mkdir -p $out
    dd if=$img of=$out/esp.img bs=$blocksize skip=$part_esp_begin count=$part_esp_count
    dd if=$img of=$out/root.img bs=$blocksize skip=$part_root_begin count=$part_root_count

    # Save partition sizes in bytes to be included in partition layout
    echo -n $(($part_esp_count * 512)) > $out/esp.size
    echo -n $(($part_root_count * 512)) > $out/root.size

    pzstd --rm -p $NIX_BUILD_CORES -19 $out/esp.img
    pzstd --rm -p $NIX_BUILD_CORES -19 $out/root.img
  '';
  dontFixup = true;
}
