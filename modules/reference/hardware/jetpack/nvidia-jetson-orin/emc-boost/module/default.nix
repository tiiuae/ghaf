# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  stdenv,
  kernel,
  kernelModuleMakeFlags,
  kmod,
}:

stdenv.mkDerivation {
  pname = "emc-cap-lift";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ kmod ] ++ kernel.moduleBuildDependencies;

  # External modules should not be PIC.
  hardeningDisable = [ "pic" ];

  makeFlags =
    kernelModuleMakeFlags
    ++ [
      "KERNEL_DIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
      "INSTALL_MOD_PATH=$(out)"
    ]
    ++ lib.optionals (stdenv.hostPlatform != stdenv.buildPlatform) [
      "CROSS_COMPILE=${stdenv.cc}/bin/${stdenv.cc.targetPrefix}"
    ];

  dontStrip = true;

  meta = {
    description = "Out-of-tree module lifting the BPMP-internal EMC frequency cap on Tegra234";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
  };
}
