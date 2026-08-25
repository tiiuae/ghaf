# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Capability-parameterized Orin GPU/display guest DTB.
{
  lib,
  pkgs,
  cap,
  board,
  kernel,
  payload,
  role,
  dtsRoot,
}:
let
  inherit (payload) expDtDefines;
  displayOnly = role == "dispvm";
  gpuDtsDir = "${dtsRoot}/gpu-vm";
  dispDtsDir = "${dtsRoot}/disp-vm";
  mainDts =
    if displayOnly then "${dispDtsDir}/tegra234-dispvm.dts" else "${gpuDtsDir}/tegra234-gpuvm.dts";
  outputName = if displayOnly then "tegra234-dispvm.dtb" else "tegra234-gpuvm.dtb";
  mainInc = "${kernel.dev}/lib/modules/${kernel.modDirVersion}/source/include";
in
pkgs.stdenv.mkDerivation {
  name = "${role}-dtb";
  dontUnpack = true;
  nativeBuildInputs = [
    pkgs.buildPackages.dtc
    pkgs.buildPackages.gcc
    pkgs.buildPackages.xxd
  ];
  buildPhase = ''
    $CC -E -nostdinc -undef -D__DTS__ ${expDtDefines}-DGHAF_DCB_DTSI='"${board.dcbDtsi}"' \
      -x assembler-with-cpp \
      -I${mainInc} \
      -I${gpuDtsDir}/nv-dt-bindings \
      -I${gpuDtsDir} \
      -I${dispDtsDir} \
      ${mainDts} > preprocessed.dts
    dtc -I dts -O dtb -o ${outputName} preprocessed.dts
  ''
  + lib.optionalString cap.display ''
    if ! fdtget ${outputName} \
         /platform-bus@70000000/display@13800000 nvidia,dcb-image >/dev/null 2>&1; then
      echo "DCB gate: display@13800000/nvidia,dcb-image not found in DTB" >&2
      exit 1
    fi
    fdtget -t bx ${outputName} \
      /platform-bus@70000000/display@13800000 nvidia,dcb-image \
      | tr -s ' \n' '\n' | grep . | sed 's/^\(.\)$/0\1/' | xxd -r -p > dcb.bin
    dcbLen=$(wc -c < dcb.bin)
    dcbHash=$(sha256sum dcb.bin | cut -d' ' -f1)
    if [ "$dcbLen" != "${board.dcbBytes}" ] || [ "$dcbHash" != "${board.dcbSha256}" ]; then
      echo "DCB payload drifted: $dcbLen bytes, sha256 $dcbHash" >&2
      echo "expected ${board.dcbBytes} bytes, sha256 ${board.dcbSha256}" >&2
      exit 1
    fi
  '';
  installPhase = ''
    mkdir -p "$out"
    cp ${outputName} "$out/"
  '';
}
