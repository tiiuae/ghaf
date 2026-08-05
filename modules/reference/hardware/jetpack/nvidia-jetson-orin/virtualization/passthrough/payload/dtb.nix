# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Capability-parameterized Orin GPU/display guest DTB.
{
  lib,
  pkgs,
  cap,
  board,
  kernel,
  dtsDir ? ../gpu-vm,
}:
let
  inherit (import ./default.nix { inherit lib; }) mkPayload;
  inherit (mkPayload cap) expDtDefines;
in
pkgs.stdenv.mkDerivation {
  name = "gpuvm-dtb";
  src = lib.fileset.toSource {
    root = dtsDir;
    fileset = lib.fileset.unions [
      (dtsDir + "/tegra234-gpuvm.dts")
      (dtsDir + "/tegra234-gpuvm-base.dtsi")
      (dtsDir + "/tegra234-gpuvm-memory.dtsi")
      (dtsDir + "/tegra234-gpuvm-proxies.dtsi")
      (dtsDir + "/tegra234-gpuvm-display.dtsi")
      (dtsDir + "/tegra234-gpuvm-engines.dtsi")
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
      $CC -E -nostdinc -undef -D__DTS__ ${expDtDefines}-DGHAF_DCB_DTSI='"${board.dcbDtsi}"' -x assembler-with-cpp \
        -I${mainInc} \
        -I${dtsDir + "/nv-dt-bindings"} \
        -I. \
        tegra234-gpuvm.dts > preprocessed.dts
      dtc -I dts -O dtb -o tegra234-gpuvm.dtb preprocessed.dts
    ''
    + lib.optionalString cap.display ''
      # Verify the embedded DCB instead of trusting its version string.
      if ! fdtget tegra234-gpuvm.dtb \
           /platform-bus@70000000/display@13800000 nvidia,dcb-image >/dev/null 2>&1; then
        echo "DCB gate: display@13800000/nvidia,dcb-image not found in DTB" >&2
        echo "(node renamed/moved, or fdtget missing) -- refusing to skip the check" >&2
        exit 1
      fi
      fdtget -t bx tegra234-gpuvm.dtb \
        /platform-bus@70000000/display@13800000 nvidia,dcb-image \
        | tr -s ' \n' '\n' | grep . | sed 's/^\(.\)$/0\1/' | xxd -r -p > dcb.bin
      dcbLen=$(wc -c < dcb.bin)
      dcbHash=$(sha256sum dcb.bin | cut -d' ' -f1)
      if [ "$dcbLen" != "${dcbBytes}" ] || [ "$dcbHash" != "${dcbSha256}" ]; then
        echo "DCB payload drifted: $dcbLen bytes, sha256 $dcbHash" >&2
        echo "expected ${dcbBytes} bytes, sha256 ${dcbSha256}" >&2
        exit 1
      fi
    '';
  installPhase = ''
    mkdir -p $out
    cp tegra234-gpuvm.dtb $out/
  '';
}
