# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Crosvm overlay for the combined Orin GPU/display guest.
{
  lib,
  pkgs,
  board,
  kernel,
  dtsDir ? ../gpu-vm,
}:
pkgs.stdenv.mkDerivation {
  name = "tegra234-guivm-crosvm-overlay";
  src = lib.fileset.toSource {
    root = dtsDir;
    fileset = lib.fileset.unions [
      (dtsDir + "/tegra234-guivm-crosvm-overlay.dts")
      (dtsDir + "/tegra234-gpuvm-memory.dtsi")
      (dtsDir + "/tegra234-gpuvm-engines.dtsi")
      (dtsDir + "/tegra234-gpuvm-display.dtsi")
      (dtsDir + "/tegra234-gpuvm-dummies.dtsi")
      (dtsDir + "/generated")
    ];
  };
  nativeBuildInputs = [
    pkgs.buildPackages.dtc
    pkgs.buildPackages.gcc
    pkgs.buildPackages.xxd
  ];
  buildPhase =
    let
      mainInc = "${kernel.dev}/lib/modules/${kernel.modDirVersion}/source/include";
      inherit (board) dcbSha256 dcbBytes;
    in
    ''
      $CC -E -nostdinc -undef -D__DTS__ -DGHAF_DCB_DTSI='"${board.dcbDtsi}"' \
        -x assembler-with-cpp \
        -I${mainInc} \
        -I${dtsDir + "/nv-dt-bindings"} \
        -I. \
        tegra234-guivm-crosvm-overlay.dts > preprocessed.dts
      dtc -@ -I dts -O dtb -o tegra234-guivm-crosvm-overlay.dtbo preprocessed.dts

      # Preserve the same board-data gate as the QEMU DTB builder.
      fdtget -t bx tegra234-guivm-crosvm-overlay.dtbo \
        /fragment@30/__overlay__/display@13800000 nvidia,dcb-image \
        | tr -s ' \n' '\n' | grep . | sed 's/^\(.\)$/0\1/' | xxd -r -p > dcb.bin
      dcbLen=$(wc -c < dcb.bin)
      dcbHash=$(sha256sum dcb.bin | cut -d' ' -f1)
      if [ "$dcbLen" != "${dcbBytes}" ] || [ "$dcbHash" != "${dcbSha256}" ]; then
        echo "DCB payload drifted: $dcbLen bytes, sha256 $dcbHash" >&2
        echo "expected ${dcbBytes} bytes, sha256 ${dcbSha256}" >&2
        exit 1
      fi

      # These labels are the typed Crosvm VFIO contract. Missing one would
      # otherwise fail only at VM startup when Crosvm patches the overlay.
      for symbol in vm_hs_p vm_cma_p scanout_p ga10b host1x vic nvdec nvjpg \
        disp_caps_pt disp_chan_pt disp_cursor_pt; do
        fdtget tegra234-guivm-crosvm-overlay.dtbo /__symbols__ "$symbol" >/dev/null
      done
    '';
  installPhase = ''
    mkdir -p $out
    cp tegra234-guivm-crosvm-overlay.dtbo $out/
  '';
}
