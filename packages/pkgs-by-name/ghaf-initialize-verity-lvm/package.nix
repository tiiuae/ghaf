# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  btrfs-progs,
  coreutils,
  findutils,
  jq,
  lvm2,
  lvm2-offline,
  runCommand,
  util-linux,
  writeShellApplication,
  zstd,
}:
let
  ghaf-initialize-verity-lvm = writeShellApplication {
    name = "ghaf-initialize-verity-lvm";
    runtimeInputs = [
      btrfs-progs
      coreutils
      findutils
      jq
      lvm2
      util-linux
      zstd
    ];
    text = builtins.replaceStrings [ "@LVM_OFFLINE@" ] [ "${lvm2-offline.bin}/bin/lvm" ] (
      builtins.readFile ./ghaf-initialize-verity-lvm.sh
    );
    meta = {
      description = "Initialize a Ghaf A/B verity LVM layout on a block device or image";
      mainProgram = "ghaf-initialize-verity-lvm";
    };
  };
in
ghaf-initialize-verity-lvm.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    tests.plan =
      runCommand "ghaf-initialize-verity-lvm-plan"
        {
          nativeBuildInputs = [
            ghaf-initialize-verity-lvm
            jq
            lvm2
            zstd
          ];
        }
        ''
          mkdir payload
          printf 'root\n' > root.raw
          printf 'verity\n' > verity.raw
          zstd root.raw -o payload/ghaf_root_1_deadbeef.raw.zst
          zstd verity.raw -o payload/ghaf_verity_1_deadbeef.raw.zst
          cat > payload/ghaf_1_deadbeef.manifest <<'EOF'
          {
            "manifest_version": 2,
            "root": { "file": "ghaf_root_1_deadbeef.raw.zst", "unpacked_size": 5 },
            "verity": { "file": "ghaf_verity_1_deadbeef.raw.zst", "unpacked_size": 7 }
          }
          EOF
          ln -s payload payload-link

          ghaf-initialize-verity-lvm \
            --update-dir payload-link --root-size-mib 1 --verity-size-mib 1 \
            --create-inactive-slots --swap-size-mib 2 --persist-size-mib 3 \
            --print-plan > plan.json
          test "$(jq -r .lv_suffix plan.json)" = 1_deadbeef
          test "$(jq -r .minimum_pv_size_mib plan.json)" = 73
          ! ghaf-initialize-verity-lvm \
            --update-dir payload --root-size-mib 1 --verity-size-mib 1 \
            --device /dev/null

          truncate -s 96M first.img
          truncate -s 96M second.img
          for image in first.img second.img; do
            ghaf-initialize-verity-lvm \
              --update-dir payload --root-size-mib 1 --verity-size-mib 1 \
              --vg-name ghaf_test --image "$image"
          done
          mkdir -p stock-lvm/archive stock-lvm/backup
          export LVM_SYSTEM_DIR=$PWD/stock-lvm
          pvck --driverloaded n --nolocking --config 'global { locking_type = 0 }' \
            --dump metadata first.img > first-metadata.txt
          pvck --driverloaded n --nolocking --config 'global { locking_type = 0 }' \
            --dump metadata second.img > second-metadata.txt
          cmp first-metadata.txt second-metadata.txt
          cmp first.img second.img
          grep 'ghaf_test {' first-metadata.txt
          grep 'root_1_deadbeef {' first-metadata.txt
          grep 'verity_1_deadbeef {' first-metadata.txt
          touch "$out"
        '';
  };
})
