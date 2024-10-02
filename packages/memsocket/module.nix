# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenv,
  lib,
  kernel,
  fetchFromGitHub,
  vmCount,
  ...
}:
stdenv.mkDerivation {
  inherit vmCount;
  name = "ivshmem-driver-${kernel.version}";

  src = fetchFromGitHub {
    owner = "tiiuae";
    repo = "shmsockproxy";
    rev = "851ca1f2d23db764dd817b15aa783d82ab17560f";
    sha256 = "sha256-8jyciVZccptGaj4u3bDj5YOCfZSsf69FH4yfqcUoB5k=";
  };

  sourceRoot = "source/module";
  hardeningDisable = [
    "pic"
    "format"
  ];
  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags = [
    "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "MODULEDIR=$(out)/lib/modules/${kernel.modDirVersion}/kernel/drivers/char"
    "CFLAGS_kvm_ivshmem.o=\"-DCONFIG_KVM_IVSHMEM_VM_COUNT=${builtins.toString vmCount}\""
  ];

  meta = with lib; {
    description = "Shared memory Linux kernel module";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
