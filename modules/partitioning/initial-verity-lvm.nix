# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Architecture-independent initial A-slot image. Platform adapters place this
# LVM PV inside their disk/container format and prepare the ESP independently.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.partitioning.verity;
  updateImage = config.system.build.ghafUpdateImage;
  buildPkgs = pkgs.pkgsBuildBuild;

  lvmConf = buildPkgs.writeText "lvm.conf" ''
    devices {
      dir = "/dev"
      scan = [ "/dev" ]
    }
    activation {
      udev_sync = 0
      udev_rules = 0
    }
  '';

  vmTools = buildPkgs.vmTools.override {
    rootModules = [
      "virtiofs"
      "virtio_pci"
      "virtio_blk"
      "virtio_balloon"
      "virtio_rng"
      "dm_mod"
    ];
  };
in
{
  config = lib.mkIf cfg.enable {
    system.build.verityLvmImage = vmTools.runInLinuxVM (
      buildPkgs.stdenvNoCC.mkDerivation {
        name = "ghaf-initial-verity-lvm";
        __structuredAttrs = false;

        buildInputs = with buildPkgs; [
          coreutils
          gawk
          jq
          lvm2
          gnused
          util-linux
          zstd
        ];
        memSize = 4096;

        preVM = ''
          set -efx
          mkdir -p "$out"
          manifest=$(find ${updateImage} -name '*.manifest' -print -quit)
          root_file=$(jq -er '.root.file' "$manifest")
          verity_file=$(jq -er '.verity.file' "$manifest")

          get_decompressed_size() {
            zstd --list -v "$1" 2>/dev/null \
              | awk '/Decompressed Size/ { match($0, /\(([0-9]+) B\)/, m); print m[1] }'
          }
          root_bytes=$(get_decompressed_size "${updateImage}/$root_file")
          verity_bytes=$(get_decompressed_size "${updateImage}/$verity_file")
          test "$root_bytes" -gt 0
          test "$verity_bytes" -gt 0

          root_mib=$(( (root_bytes + 1048575) / 1048576 + 512 ))
          verity_mib=$(( (verity_bytes + 1048575) / 1048576 + 16 ))
          lvm_mib=$(( root_mib + verity_mib + 64 ))
          ${buildPkgs.qemu}/bin/qemu-img create -f raw "$out/system.img" "''${lvm_mib}M"

          mkdir -p xchg
          printf '%s\n' "$root_mib" > xchg/root_size_mib
          printf '%s\n' "$verity_mib" > xchg/verity_size_mib
        '';

        QEMU_OPTS = ''-drive file="$out"/system.img,if=virtio,cache=unsafe,werror=report,format=raw'';

        postVM = ''
          lvm_size=$(stat -c%s "$out/system.img")
          printf '%s\n' "$lvm_size" > "$out/system.raw_size"
          cp xchg/root_size_mib "$out/root_size_mib"
          cp xchg/verity_size_mib "$out/verity_size_mib"
          zstd --compress --rm "$out/system.img" -o "$out/system.img.zst"
        '';

        buildCommand = ''
          export LVM_SYSTEM_DIR=/tmp/lvm
          mkdir -p /tmp/lvm
          cp ${lvmConf} /tmp/lvm/lvm.conf

          manifest=$(find ${updateImage} -name '*.manifest' -print -quit)
          root_file=$(jq -er '.root.file' "$manifest")
          verity_file=$(jq -er '.verity.file' "$manifest")
          lv_suffix=$(printf '%s' "$root_file" | sed 's/^ghaf_root_//; s/\.raw\.zst$//')
          test -n "$lv_suffix"

          pvcreate /dev/vda
          vgcreate pool /dev/vda
          root_mib=$(cat /tmp/xchg/root_size_mib)
          verity_mib=$(cat /tmp/xchg/verity_size_mib)
          lvcreate -L "''${root_mib}M" -n "root_$lv_suffix" pool
          lvcreate -L "''${verity_mib}M" -n "verity_$lv_suffix" pool
          zstd -d "${updateImage}/$root_file" --stdout \
            | dd of="/dev/pool/root_$lv_suffix" bs=4M conv=notrunc status=progress
          zstd -d "${updateImage}/$verity_file" --stdout \
            | dd of="/dev/pool/verity_$lv_suffix" bs=4M conv=notrunc status=progress
          vgchange -an pool
        '';
      }
    );
  };
}
