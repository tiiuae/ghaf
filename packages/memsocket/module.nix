# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenv,
  lib,
  kernel,
  fetchFromGitHub,
  shmSlots,
  ...
}:
stdenv.mkDerivation {
  inherit shmSlots;
  name = "ivshmem-driver-${kernel.version}";

  src = fetchFromGitHub {
    owner = "tiiuae";
    repo = "shmsockproxy";
    rev = "ea446dfe3be66004867b6b369950eb16dc04c421";
    sha256 = "sha256-qxrDHxM2z/bIVsTuNx45zZOjp4+BLheWrvco946OMQM=";
  };

  sourceRoot = "source/module";
  hardeningDisable = [
    "pic"
    "format"
  ];
  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags =
    [
      "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
      "MODULEDIR=$(out)/lib/modules/${kernel.modDirVersion}/kernel/drivers/char"
      "CFLAGS_kvm_ivshmem.o=\"-DCONFIG_KVM_IVSHMEM_SHM_SLOTS=${builtins.toString shmSlots}\""
      "ARCH=${stdenv.hostPlatform.linuxArch}"
      "INSTALL_MOD_PATH=${placeholder "out"}"
    ]
    ++ lib.optionals (stdenv.hostPlatform != stdenv.buildPlatform) [
      "CROSS_COMPILE=${stdenv.cc}/bin/${stdenv.cc.targetPrefix}"
    ];

  CROSS_COMPILE = lib.optionalString (
    stdenv.hostPlatform != stdenv.buildPlatform
  ) "${stdenv.cc}/bin/${stdenv.cc.targetPrefix}";

  meta = with lib; {
    description = "Shared memory Linux kernel module";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
