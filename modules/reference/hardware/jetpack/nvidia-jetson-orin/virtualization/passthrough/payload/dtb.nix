# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Cap-parameterized Orin guest DTB builder, shared by gpu-vm (and gui-vm).
# Extracted verbatim from gpu-vm/default.nix's `gpuvm-dtb` derivation; the only
# change is that the cpp -D strip/resize flags come from `(mkPayload cap).expDtDefines`
# and the DTS sources are taken from `dtsDir` (defaults to ../gpu-vm) instead of `./.`.
# The DCB sha256 verify block is preserved exactly.
{
  lib,
  pkgs,
  cap,
  # Host kernel whose mainline dt-bindings headers the .dts includes reference.
  kernel,
  # Directory holding the composition root + component .dtsi fragments +
  # generated/ + nv-dt-bindings/. gpu-vm's own sources by default.
  dtsDir ? ../gpu-vm,
}:
let
  inherit (import ./default.nix { inherit lib; }) mkPayload;
  # cpp -D flags that strip/resize guest DT nodes for this capability payload.
  inherit (mkPayload cap) expDtDefines;
in
pkgs.stdenv.mkDerivation {
  name = "gpuvm-dtb";
  # Composition root + component .dtsi fragments (see the include list in
  # tegra234-gpuvm.dts); generated/ holds the pinned stock-derived DCB.
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
  # Build-platform tools: preprocesses + compiles a device tree (arch-agnostic
  # text) at build time, so it runs on the builder -- buildPackages makes `gcc`
  # the native compiler in a cross build.
  nativeBuildInputs = [
    pkgs.buildPackages.dtc
    pkgs.buildPackages.gcc
    pkgs.buildPackages.xxd
  ];
  buildPhase =
    let
      mainInc = "${kernel.dev}/lib/modules/${kernel.modDirVersion}/source/include";
      # Stock R36.5 P3737/P3701 AGX DCB pin (full payload, not just the
      # embedded version string -- a wrong-board blob can carry a
      # valid-looking version with foreign SOR/connector routing).
      dcbSha256 = "e0d92e6dbf1ffef266cfd2e192847e76f8d88c19c55430f2f5d4aaf69494a2fc";
      dcbBytes = "8407";
    in
    ''
      # $CC = stdenv's compiler (triple-prefixed under cross); -E only
      # preprocesses, so the target triple is irrelevant to the text output.
      $CC -E -nostdinc -undef -D__DTS__ ${expDtDefines}-x assembler-with-cpp \
        -I${mainInc} \
        -I${dtsDir + "/nv-dt-bindings"} \
        -I. \
        tegra234-gpuvm.dts > preprocessed.dts
      dtc -I dts -O dtb -o tegra234-gpuvm.dtb preprocessed.dts
    ''
    # The DCB gate only applies when the capability retains the display node.
    # Key this on the same eval-time capability instead of fdtget's exit code,
    # which would silently skip the check if the node were renamed or moved.
    + lib.optionalString cap.display ''
      # Verify the DCB payload that actually landed in the DTB against the
      # pinned stock AGX blob; fail the build on any drift. If the display
      # node cannot be extracted, fail loudly rather than skipping the gate.
      if ! fdtget tegra234-gpuvm.dtb \
           /platform-bus@70000000/display@13800000 nvidia,dcb-image >/dev/null 2>&1; then
        echo "DCB gate: display@13800000/nvidia,dcb-image not found in DTB" >&2
        echo "(node renamed/moved, or fdtget missing) -- refusing to skip the check" >&2
        exit 1
      fi
      # -t bx prints space-separated hex bytes, UNPADDED (e.g. `0 d 55 aa`),
      # so zero-pad each to two digits before xxd -r -p folds the whole
      # payload back to binary in one pass.
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
