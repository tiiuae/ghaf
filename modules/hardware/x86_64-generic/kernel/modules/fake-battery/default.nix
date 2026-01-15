# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  stdenv,
  kernel,
  kernelModuleMakeFlags,
  kmod,
  # Pass e.g. (import <nixpkgs> {}).linuxPackages.kernel when calling manually,
  # or let NixOS inject it via boot.extraModulePackages usage.
}:

stdenv.mkDerivation {
  pname = "fake-battery";
  version = "0.1.0";

  # The source is this directory (contains fake_battery.c and Makefile)
  src = ./.;

  # Kernel exposes a list of build-time deps for external modules.
  nativeBuildInputs = [ kmod ] ++ kernel.moduleBuildDependencies;

  # External modules should not be PIC.
  hardeningDisable = [
    "pic"
  ];

  makeFlags =
    kernelModuleMakeFlags
    ++ [
      # Variable refers to the local Makefile.
      "KERNEL_DIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
      # Variable of the Linux src tree's main Makefile.
      "INSTALL_MOD_PATH=$(out)"
    ]
    ++ lib.optionals (stdenv.hostPlatform != stdenv.buildPlatform) [
      "CROSS_COMPILE=${stdenv.cc}/bin/${stdenv.cc.targetPrefix}"
    ];

  # Avoid stripping which could interfere with signatures / debugging.
  dontStrip = true;

  meta = {
    description = "Out-of-tree fake battery power_supply Linux kernel module";
    license = lib.licenses.gpl2Plus;
    platforms = kernel.meta.platforms or lib.platforms.linux;
  };
}
