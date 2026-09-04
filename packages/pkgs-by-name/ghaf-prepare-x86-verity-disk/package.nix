# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  bmaptool,
  coreutils,
  cryptsetup,
  dosfstools,
  findutils,
  gawk,
  ghaf-initialize-verity-lvm,
  ghaf-wrap-luks-image,
  gptfdisk,
  jq,
  mtools,
  runCommand,
  writeShellApplication,
  zstd,
}:
let
  ghaf-prepare-x86-verity-disk = writeShellApplication {
    name = "ghaf-prepare-x86-verity-disk";
    runtimeInputs = [
      bmaptool
      coreutils
      dosfstools
      findutils
      gawk
      ghaf-initialize-verity-lvm
      ghaf-wrap-luks-image
      gptfdisk
      jq
      mtools
      zstd
    ];
    text = builtins.readFile ./ghaf-prepare-x86-verity-disk.sh;
    meta = {
      description = "Build a Ghaf x86 secure A/B disk from regular files";
      mainProgram = "ghaf-prepare-x86-verity-disk";
      platforms = [ "x86_64-linux" ];
    };
  };
in
ghaf-prepare-x86-verity-disk.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    tests.plan =
      runCommand "ghaf-prepare-x86-verity-disk-plan"
        {
          nativeBuildInputs = [
            ghaf-prepare-x86-verity-disk
            jq
            zstd
          ];
        }
        ''
          mkdir payload
          printf 'root\n' > root.raw
          printf 'verity\n' > verity.raw
          zstd root.raw -o payload/ghaf_root_1_deadbeef.raw.zst
          zstd verity.raw -o payload/ghaf_verity_1_deadbeef.raw.zst
          touch payload/ghaf_kernel_1_deadbeef.efi systemd-boot.efi trust.json
          cat > payload/ghaf_1_deadbeef.manifest <<'EOF'
          {
            "manifest_version": 2,
            "version": "1",
            "root_verity_hash": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            "root": { "file": "ghaf_root_1_deadbeef.raw.zst", "unpacked_size": 5 },
            "verity": { "file": "ghaf_verity_1_deadbeef.raw.zst", "unpacked_size": 7 }
          }
          EOF
          ghaf-prepare-x86-verity-disk \
            --update-dir payload --systemd-boot systemd-boot.efi \
            --trust-inventory trust.json --image-size-mib 4602 \
            --root-size-mib 1 --verity-size-mib 1 --swap-size-mib 1 \
            --persist-size-mib 1 --boot-timeout menu-force \
            --print-plan > plan.json
          test "$(jq -r .minimum_image_size_mib plan.json)" = 4602
          ! ghaf-prepare-x86-verity-disk \
            --update-dir payload --systemd-boot systemd-boot.efi \
            --trust-inventory trust.json --image-size-mib 4601 \
            --root-size-mib 1 --verity-size-mib 1 --swap-size-mib 1 \
            --persist-size-mib 1 --boot-timeout menu-force --print-plan
          touch "$out"
        '';
    tests.image =
      runCommand "ghaf-prepare-x86-verity-disk-image"
        {
          nativeBuildInputs = [
            cryptsetup
            ghaf-prepare-x86-verity-disk
            gptfdisk
            mtools
            zstd
          ];
        }
        ''
          mkdir payload
          printf 'root\n' > root.raw
          printf 'verity\n' > verity.raw
          zstd root.raw -o payload/ghaf_root_1_deadbeef.raw.zst
          zstd verity.raw -o payload/ghaf_verity_1_deadbeef.raw.zst
          touch payload/ghaf_kernel_1_deadbeef.efi systemd-boot.efi
          printf '{"external":false}\n' > trust.json
          cat > payload/ghaf_1_deadbeef.manifest <<'EOF'
          {
            "manifest_version": 2,
            "version": "1",
            "root_verity_hash": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            "root": { "file": "ghaf_root_1_deadbeef.raw.zst", "unpacked_size": 5 },
            "verity": { "file": "ghaf_verity_1_deadbeef.raw.zst", "unpacked_size": 7 }
          }
          EOF
          ghaf-prepare-x86-verity-disk \
            --update-dir payload --systemd-boot systemd-boot.efi \
            --trust-inventory trust.json --image-size-mib 4600 \
            --root-size-mib 1 --verity-size-mib 1 --swap-size-mib 0 \
            --persist-size-mib 0 --boot-timeout menu-force --output "$out"

          test -s "$out/ghaf-image.raw.zst"
          test -s "$out/ghaf-image.bmap"
          cmp trust.json "$out/public-trust.json"
          zstd --decompress "$out/ghaf-image.raw.zst" -o image.raw
          sgdisk --verify image.raw
          test "$(sgdisk -i 1 image.raw | awk '/Partition name:/ { print $3 }')" = "'ESP'"
          test "$(sgdisk -i 2 image.raw | awk '/Partition name:/ { print $3 }')" = "'disk-disk1-luks'"
          sgdisk -i 2 image.raw | grep -Fq \
            'Partition GUID code: CA7D7CCB-63ED-4C53-861C-1742536059CC'
          esp_first=$(sgdisk -i 1 image.raw | awk '/First sector:/ { print $3 }')
          luks_first=$(sgdisk -i 2 image.raw | awk '/First sector:/ { print $3 }')
          mdir -i "image.raw@@$((esp_first * 512))" ::EFI/Linux/ghaf-1-0123456789abcdef.efi
          dd if=image.raw of=luks-header.img bs=512 skip="$luks_first" count=65536 status=none
          cryptsetup isLuks --type luks2 luks-header.img
        '';
  };
})
