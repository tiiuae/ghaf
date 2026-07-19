# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# ghaf-qemu pinned to 10.1.5, plus the NVIDIA BPMP guest bridge: a sysbus MMIO
# device forwarding a guest's BPMP messages to the host proxy via /dev/bpmp-host.
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

    patches = (prev.patches or [ ]) ++ [ ./patches/0001-nvidia-bpmp-guest-hooks.patch ] ++ extraPatches;

    # The device is carried as source rather than as ~180 lines of `+` in a diff.
    postPatch = (prev.postPatch or "") + ''
      cp ${./sources/hw/misc/nvidia_bpmp_guest.c} hw/misc/nvidia_bpmp_guest.c
      cp ${./sources/include/hw/misc/nvidia_bpmp_guest.h} include/hw/misc/nvidia_bpmp_guest.h
      chmod u+w hw/misc/nvidia_bpmp_guest.c include/hw/misc/nvidia_bpmp_guest.h

      # ghaf-qemu's 0006-ivshmem-flat-memory-support.patch is written against QEMU 11,
      # where sysbus.h lives at include/hw/core/. In 10.1 it is still include/hw/.
      substituteInPlace hw/misc/ivshmem-pci.c \
        --replace-fail '#include "hw/core/sysbus.h"' '#include "hw/sysbus.h"'
    '';
  }
)
