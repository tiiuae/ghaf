# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenv,
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
    rev = "2357926b94ed12c050fdbfbfc0f248393a4c9ea1";
    sha256 = "sha256-9KlHuVbe5qvjRUXj7oyJ1X7CLvqj7/OoVGDWRqpIY2s=";
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

  meta = {
    description = "Shared memory Linux kernel module";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
