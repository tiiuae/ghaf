# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
(_final: prev: {
  qemu_kvm = prev.qemu_kvm.overrideAttrs (
    _final: prev: { patches = prev.patches ++ [ 
      ./patches/0001-nvidia-bpmp-guest-driver-initial-commit.patch
      ./patches/0002-NOP_PREDEFINED_DTB_MEMORY.patch
      ./patches/0004-vfio-platform-Add-mmio-base-property-to-define-start.patch
    ]; }
  );
})
