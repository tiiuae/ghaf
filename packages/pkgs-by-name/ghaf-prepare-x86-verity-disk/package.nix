# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  bmaptool,
  coreutils,
  cryptsetup,
  dosfstools,
  findutils,
  ghaf-initialize-verity-lvm,
  ghaf-update-manifest,
  pkgs,
  util-linux,
  gptfdisk,
  jq,
  mtools,
  runCommand,
  writeShellApplication,
  zstd,
}:
let
  fixture = ''
    mkdir payload
    printf 'root\n' > root.raw
    printf 'verity\n' > verity.raw
    zstd root.raw -o payload/ghaf_root_1_deadbeef.raw.zst
    zstd verity.raw -o payload/ghaf_verity_1_deadbeef.raw.zst
    touch payload/ghaf_kernel_1_deadbeef.efi systemd-boot.efi
    printf '{"target":"test","generation":1,"publicTrustDigests":{}}\n' > trust.json
    printf '%064d\n' 0 > hash
    ghaf-update-manifest generate --version 1 --system x86_64-linux --build-system x86_64-linux \
      --target test --generation 1 --hash-file hash --root-image payload/ghaf_root_1_deadbeef.raw.zst \
      --verity-image payload/ghaf_verity_1_deadbeef.raw.zst --kernel-image payload/ghaf_kernel_1_deadbeef.efi \
      --root-unpacked-size 5 --verity-unpacked-size 7 --manifest payload/ghaf_1_deadbeef.manifest
    prepare() {
      ghaf-prepare-x86-verity-disk --update-dir payload --systemd-boot systemd-boot.efi \
        --trust-inventory trust.json --root-size-mib 1 --verity-size-mib 1 \
        --boot-timeout menu-force "$@"
    }
  '';
  runVM = import ../../../lib/image-builder-vm.nix { inherit pkgs; };
  buildImage =
    { imageSizeMiB, buildCommand }:
    runVM (
      runCommand "ghaf-x86-verity-disk" {
        nativeBuildInputs = [
          ghaf-prepare-x86-verity-disk
          ghaf-update-manifest
          cryptsetup
          gptfdisk
          mtools
          zstd
          bmaptool
        ];
        preVM = ''
          diskImage=$PWD/ghaf-image.raw
          truncate -s ${toString imageSizeMiB}M "$diskImage"
        '';
        postVM = ''
          bmaptool create "$diskImage" -o "$out/ghaf-image.bmap"
          zstd --compress -T8 "$diskImage" -o "$out/ghaf-image.raw.zst"
        '';
      } buildCommand
    );
  ghaf-prepare-x86-verity-disk = writeShellApplication {
    name = "ghaf-prepare-x86-verity-disk";
    runtimeInputs = [
      coreutils
      dosfstools
      findutils
      ghaf-initialize-verity-lvm
      util-linux
      gptfdisk
      jq
      mtools
    ];
    text = builtins.readFile ./ghaf-prepare-x86-verity-disk.sh;
    meta = {
      description = "Populate a Ghaf x86 secure A/B disk inside a build VM";
      mainProgram = "ghaf-prepare-x86-verity-disk";
      platforms = [ "x86_64-linux" ];
    };
  };
in
ghaf-prepare-x86-verity-disk.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    inherit buildImage;
    tests.plan =
      runCommand "ghaf-prepare-x86-verity-disk-plan"
        {
          nativeBuildInputs = [
            ghaf-prepare-x86-verity-disk
            ghaf-update-manifest
            jq
            zstd
          ];
        }
        ''
          ${fixture}
          prepare --image-size-mib 4602 --swap-size-mib 1 --persist-size-mib 1 \
            --print-plan > plan.json
          test "$(jq -r .minimum_image_size_mib plan.json)" = 4602
          ! prepare --image-size-mib 4601 --swap-size-mib 1 --persist-size-mib 1 --print-plan
          for option in --output --image-size-mib --PATH; do
            ! ghaf-prepare-x86-verity-disk "$option" 2>error.log
            grep -q '^Usage:' error.log
          done
          touch "$out"
        '';
    tests.image = buildImage {
      imageSizeMiB = 4600;
      buildCommand = ''
        ${fixture}
        prepare --disk /dev/vda --image-size-mib 4600 --swap-size-mib 0 --persist-size-mib 0 --output "$out"
        cmp trust.json "$out/public-trust.json"
        sgdisk --verify /dev/vda
        sgdisk -i 2 /dev/vda | grep -Fq 'Partition GUID code: CA7D7CCB-63ED-4C53-861C-1742536059CC'
        mdir -i /dev/vda1 ::EFI/Linux/ghaf-1-0000000000000000.efi
        cryptsetup isLuks --type luks2 /dev/vda2
        test "$(cryptsetup luksUUID /dev/vda2)" = 3e7f3d25-695a-429d-8d34-2d0a18979d7d
      '';
    };
  };
})
