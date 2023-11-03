# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
(final: prev: {
  qemu_kvm = prev.qemu_kvm.overrideAttrs (_final: prev: {
    patches = prev.patches ++ [./acpi-devices-passthrough.patch];
  });
})
