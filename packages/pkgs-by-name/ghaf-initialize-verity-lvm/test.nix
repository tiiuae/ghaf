# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  initializer,
  ghaf-update-manifest,
}:
let
  runVM = import ../../../lib/image-builder-vm.nix { inherit pkgs; };
in
runVM (
  pkgs.runCommand "ghaf-verity-storage-vm-test"
    {
      nativeBuildInputs = with pkgs; [
        initializer
        ghaf-update-manifest
        zstd
        cryptsetup
        lvm2
        util-linux
        btrfs-progs
        jq
      ];
      preVM = ''
        diskImage=$PWD/storage.raw
        truncate -s 320M "$diskImage"
      '';
    }
    ''
          printf 'root\n' > root.raw
          printf 'verity\n' > verity.raw
          zstd root.raw -o ghaf_root_1_deadbeef.raw.zst
          zstd verity.raw -o ghaf_verity_1_deadbeef.raw.zst
          printf 'kernel' > kernel.efi
          printf '%064d\n' 0 > hash
          ghaf-update-manifest generate --version 1 --system x86_64-linux --build-system x86_64-linux \
            --target test --generation 1 --hash-file hash --root-image ghaf_root_1_deadbeef.raw.zst \
            --verity-image ghaf_verity_1_deadbeef.raw.zst --kernel-image kernel.efi \
            --root-unpacked-size 5 --verity-unpacked-size 7 --manifest manifest.json
          initialize() {
            ghaf-initialize-verity-lvm --manifest manifest.json --root-size-mib 4 --verity-size-mib 4 \
              --create-inactive-slots --swap-size-mib 4 --persist-size-mib 128 "$@"
          }
          initialize --print-plan | jq -e '.minimum_pv_size_mib == 212'
          cp manifest.json valid.json
          before=$(sha256sum /dev/vda)
          for length in 4 6 4194305; do
            jq --argjson length "$length" '.root.unpacked_size = $length' valid.json > manifest.json
            if initialize --image /dev/vda; then exit 1; fi
            test "$(sha256sum /dev/vda)" = "$before"
          done
          cp valid.json manifest.json
        cp ghaf_root_1_deadbeef.raw.zst saved-root.zst
        head -c 1048576 /dev/zero | zstd -f -o ghaf_root_1_deadbeef.raw.zst
        if initialize --image /dev/vda; then exit 1; fi
        test "$(sha256sum /dev/vda)" = "$before"
        mv saved-root.zst ghaf_root_1_deadbeef.raw.zst
          printf 'test-passphrase' > key
          initialize --image /dev/vda --luks-uuid 01234567-89ab-4cde-8fab-0123456789ab --key-file key
          cryptsetup isLuks --type luks2 /dev/vda
          printf wrong > wrong-key
          ! cryptsetup open --test-passphrase --key-file wrong-key /dev/vda
          cryptsetup open --key-file key /dev/vda test-pool
          export LVM_SYSTEM_DIR=$PWD/lvm
          mkdir "$LVM_SYSTEM_DIR"
          echo 'devices { use_devicesfile = 0 } activation { udev_sync = 0 udev_rules = 0 }' > "$LVM_SYSTEM_DIR/lvm.conf"
          vgchange -ay pool
          vgmknodes pool
          cmp -n 5 root.raw /dev/pool/root_1_deadbeef
          cmp -n 7 verity.raw /dev/pool/verity_1_deadbeef
          test "$(blockdev --getsize64 /dev/pool/root_empty)" = 4194304
          test "$(blockdev --getsize64 /dev/pool/verity_empty)" = 4194304
          test "$(blkid -s TYPE -o value /dev/pool/swap)" = swap
          lvrename pool root_empty root_candidate
          lvextend -l +100%FREE /dev/pool/persist
          mkdir mountpoint
          mount /dev/pool/persist mountpoint
          btrfs filesystem resize max mountpoint
          echo preserved > mountpoint/sentinel
          umount mountpoint
          vgchange -an pool
          cryptsetup close test-pool
          cryptsetup open --key-file key /dev/vda test-pool
          vgchange -ay pool
          mount /dev/pool/persist mountpoint
          grep -qx preserved mountpoint/sentinel
          test -b /dev/pool/root_candidate
          umount mountpoint
          vgchange -an pool
          cryptsetup close test-pool
          # Exercise the unencrypted Orin layout on the same disposable scratch disk.
      wipefs --all /dev/vda
      initialize --image /dev/vda
      ! cryptsetup isLuks /dev/vda
      vgchange -ay pool
      cmp -n 5 root.raw /dev/pool/root_1_deadbeef
      cmp -n 7 verity.raw /dev/pool/verity_1_deadbeef
      test -b /dev/pool/root_empty
      vgchange -an pool
      touch "$out"
    ''
)
