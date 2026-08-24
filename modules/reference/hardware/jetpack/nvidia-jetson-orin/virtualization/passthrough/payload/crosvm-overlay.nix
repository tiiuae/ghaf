# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Crosvm overlay for the combined Orin GPU/display guest.
{
  lib,
  pkgs,
  cap,
  board,
  kernel,
  dtsDir ? ../gpu-vm,
  overlayDts ? dtsDir + "/tegra234-guivm-crosvm-overlay.dts",
}:
let
  inherit (import ./default.nix { inherit lib; }) mkPayload;
  payload = mkPayload cap;
  overlayName = "tegra234-${
    if cap.display && !cap.gpu then
      "dispvm"
    else if cap.display then
      "guivm"
    else
      "gpuvm"
  }-crosvm-overlay";
in
pkgs.stdenv.mkDerivation {
  name = overlayName;
  dontUnpack = true;
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
      $CC -E -nostdinc -undef -D__DTS__ ${payload.expDtDefines}-DGHAF_DCB_DTSI='"${board.dcbDtsi}"' \
        -x assembler-with-cpp \
        -I${mainInc} \
        -I${dtsDir + "/nv-dt-bindings"} \
        -I${dtsDir} \
        -I${../disp-vm} \
        ${overlayDts} > preprocessed.dts
      dtc -@ -I dts -O dtb -o ${overlayName}.dtbo preprocessed.dts

      # Preserve the same board-data gate as the QEMU DTB builder.
    ''
    + lib.optionalString cap.display ''
      fdtget -t bx ${overlayName}.dtbo \
        /fragment@30/__overlay__/display@13800000 nvidia,dcb-image \
        | tr -s ' \n' '\n' | grep . | sed 's/^\(.\)$/0\1/' | xxd -r -p > dcb.bin
      dcbLen=$(wc -c < dcb.bin)
      dcbHash=$(sha256sum dcb.bin | cut -d' ' -f1)
      if [ "$dcbLen" != "${dcbBytes}" ] || [ "$dcbHash" != "${dcbSha256}" ]; then
        echo "DCB payload drifted: $dcbLen bytes, sha256 $dcbHash" >&2
        echo "expected ${dcbBytes} bytes, sha256 ${dcbSha256}" >&2
        exit 1
      fi

    ''
    + ''
      # These labels are the typed Crosvm VFIO contract. Missing one would
      # otherwise fail only at VM startup when Crosvm patches the overlay.
      for symbol in ${lib.escapeShellArgs (map (device: device.dtSymbol) payload.crosvmDevices)}; do
        fdtget ${overlayName}.dtbo /__symbols__ "$symbol" >/dev/null
      done
    ''
    + lib.optionalString (!cap.display || cap.gpu) ''
      # vm_cma_p backs both NVIDIA carveouts and the guest's reusable CMA
      # pool. It must remain visible as System RAM in addition to the disabled
      # VFIO resource anchor that Crosvm patches above.
      test "$(fdtget -t s ${overlayName}.dtbo \
        /fragment@10/__overlay__/memory@80000000 device_type)" = memory
      set -- $(fdtget -t x ${overlayName}.dtbo \
        /fragment@10/__overlay__/memory@80000000 reg)
      test "$1 $2 $3 $4" = "0 80000000 0 30000000"
    ''
    + lib.optionalString (cap.display && !cap.gpu) ''
      test "$(fdtget -t s ${overlayName}.dtbo \
        /fragment@10/__overlay__/memory@b8000000 device_type)" = memory
      set -- $(fdtget -t x ${overlayName}.dtbo \
        /fragment@10/__overlay__/memory@b8000000 reg)
      test "$1 $2 $3 $4 $5 $6 $7 $8" = \
        "0 b8000000 0 2e000000 2 0 0 1a000000"
    ''
    + lib.optionalString cap.host1x ''
      # Child VFIO regs are patched to Crosvm's allocated GPAs, so host1x
      # must retain an identity ranges property when the overlay is applied.
      fdtget ${overlayName}.dtbo \
        /fragment@20/__overlay__/host1x@13e00000 ranges >/dev/null
    '';
  installPhase = ''
    mkdir -p $out
    cp ${overlayName}.dtbo $out/
  '';

  passthru.fileName = "${overlayName}.dtbo";
}
