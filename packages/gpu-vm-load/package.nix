# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# gpu-vm-load: prebuilt CUDA smoke-test binary for the gpu-vm passthrough. The
# guest can't compile (no toolkit) and Jetson nvcc can't run on the x86 builder,
# so it's built here from hand-written PTX (vadd.ptx) driven by runner.c over the
# Driver API. See runner.c for the self-contained/RPATH details.
{
  stdenv,
  nvidia-jetpack,
}:
stdenv.mkDerivation {
  pname = "gpu-vm-load";
  version = "1.0";
  src = ./.;

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    # -I. so the assembler's .incbin finds vadd.ptx in the build dir.
    $CC -I. runner.c -o gpu-vm-load \
      -L${nvidia-jetpack.l4t-cuda}/lib -l:libcuda.so.1 \
      -Wl,-rpath,${nvidia-jetpack.l4t-cuda}/lib
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 gpu-vm-load $out/bin/gpu-vm-load
    runHook postInstall
  '';

  meta = {
    description = "CUDA compute-load smoke test for the gpu-vm passthrough";
    platforms = [ "aarch64-linux" ];
    mainProgram = "gpu-vm-load";
  };
}
