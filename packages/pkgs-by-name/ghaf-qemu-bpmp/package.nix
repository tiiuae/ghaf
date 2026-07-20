# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# ghaf-qemu pinned to 10.1.5, plus two NVIDIA sync-forward guest bridges (sysbus
# MMIO devices relaying guest IPC to host proxies): BPMP via /dev/bpmp-host, and
# DCE display IPC via /dev/dce-host. The BPMP bridge emits its own guest /bpmp DT
# node; the DCE one does not (the GPU-VM's hand-written DTS carries dce-virtual-pa
# directly).
#
# QEMU removed `-device vfio-platform` in 10.2 with nothing replacing it, and
# passing an on-SoC MMIO device (the Orin's MGBE0) to a guest needs it; 10.1.5
# is the last release that has it. Only the VM receiving such a device uses this
# QEMU (set via microvm.qemu.package); everything else stays on pkgs.ghaf-qemu.
#
# The pin is a security liability: net-vm is network-facing and won't get QEMU
# fixes past 10.1.x. Revisit if upstream restores platform passthrough.
#
# extraPatches/variantName let a variant (see ../ghaf-qemu-bpmp-gpu) add patches
# and rename the binary. pkgs-by-name auto-calls with {}, so both default to the
# net-vm build -- pkgs.ghaf-qemu-bpmp is byte-identical to before.
{
  ghaf-qemu,
  fetchurl,
  lib,
  extraPatches ? [ ],
  variantName ? "",
  ...
}:
ghaf-qemu.overrideAttrs (
  _final: prev: rec {
    pname = "ghaf-qemu-bpmp${variantName}";
    version = "10.1.5";

    src = fetchurl {
      url = "https://download.qemu.org/qemu-${version}.tar.xz";
      hash = "sha256-HxIJtNuC5sRBfq9ufgsHNWNXKgQtn7dJKwhLplqcBpM=";
    };

    # ghaf-qemu's base patch set advanced to target QEMU 11; the x86 laptop-ACPI
    # series (extended-GPE / Battery / AC-adapter / lid-button) no longer applies
    # to the pinned 10.1.5 and is irrelevant to the Orin aarch64 microvm. Drop it
    # so the package builds; keep everything else.
    patches =
      (lib.filter (p: !(lib.hasInfix "hw-acpi-" (baseNameOf p))) (prev.patches or [ ]))
      ++ [
        ./patches/0001-nvidia-bpmp-guest-hooks.patch
        ./patches/0002-nvidia-dce-guest-hooks.patch
      ]
      ++ extraPatches;

    # The device is carried as source rather than as ~180 lines of `+` in a diff.
    postPatch = (prev.postPatch or "") + ''
      cp ${./sources/hw/misc/nvidia_bpmp_guest.c} hw/misc/nvidia_bpmp_guest.c
      cp ${./sources/include/hw/misc/nvidia_bpmp_guest.h} include/hw/misc/nvidia_bpmp_guest.h
      cp ${./sources/hw/misc/nvidia_dce_guest.c} hw/misc/nvidia_dce_guest.c
      cp ${./sources/include/hw/misc/nvidia_dce_guest.h} include/hw/misc/nvidia_dce_guest.h
      chmod u+w hw/misc/nvidia_bpmp_guest.c include/hw/misc/nvidia_bpmp_guest.h \
        hw/misc/nvidia_dce_guest.c include/hw/misc/nvidia_dce_guest.h

      # NVIDIA_DCE_GUEST Kconfig symbol is appended here rather than via a
      # line-numbered hunk in 0002 -- the hw/misc/Kconfig region around the
      # bpmp entry shifts against QEMU 10.1.5, so a context patch is fragile.
      # Config order is irrelevant; hw/arm/Kconfig `select`s it (via the patch).
      printf '\nconfig NVIDIA_DCE_GUEST\n    bool\n' >> hw/misc/Kconfig

      # ghaf-qemu's 0006-ivshmem-flat-memory-support.patch is written against QEMU 11,
      # where sysbus.h lives at include/hw/core/. In 10.1 it is still include/hw/.
      substituteInPlace hw/misc/ivshmem-pci.c \
        --replace-fail '#include "hw/core/sysbus.h"' '#include "hw/sysbus.h"'
    '';
  }
)
