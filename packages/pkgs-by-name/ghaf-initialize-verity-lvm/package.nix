# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  btrfs-progs,
  coreutils,
  findutils,
  jq,
  lvm2,
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
    text = builtins.readFile ./ghaf-initialize-verity-lvm.sh;
    meta = {
      description = "Initialize a Ghaf A/B verity LVM layout on a block device";
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
          touch "$out"
        '';
  };
})
