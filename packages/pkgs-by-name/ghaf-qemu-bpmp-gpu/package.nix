# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# GPU-VM variant of ghaf-qemu-bpmp. Same QEMU 10.1.5 + BPMP bridge, plus two
# patches the GPU needs and net-vm does not:
#   - vfio-platform mmio-base + a large platform bus, for 1:1 GPA=HPA mapping of
#     the GPU's large reserved-memory MMIO regions.
#   - a predefined-DTB path so gpu-vm can supply a hand-written guest device tree
#     (GPU + display + engines; too complex to emit from a QEMU FDT binding).
# Kept a SEPARATE binary so net-vm's memory map stays byte-identical to
# ghaf-qemu-bpmp.
#
# LIFECYCLE / EOL: pins QEMU 10.1.5, the last release with `-device vfio-platform`
# (removed in 10.2, no replacement). This extends that frozen branch to a second
# DMA-capable, network-adjacent VM, so a guest-reachable VFIO CVE on 10.1 has a
# hardware-privileged blast surface with no forward bump path. Mitigations: keep
# gpu-vm off WAN-adjacent segments and firewalled from untrusted app-VMs; migrate
# net-vm + gpu-vm together to a supported successor (vfio-user / maintained fork)
# when one exists.
{ ghaf-qemu-bpmp }:
ghaf-qemu-bpmp.override {
  variantName = "-gpu";
  # irqfd fast path was validated on MGBE0 only; the GPU/host1x/display devices have
  # not been tried on it and the display bring-up depends on their interrupt behaviour.
  withIrqfdFastPath = false;
  extraPatches = [
    ../ghaf-qemu-bpmp/patches/0002-vfio-platform-mmio-base.patch
    ../ghaf-qemu-bpmp/patches/0003-nop-predefined-dtb-memory.patch
  ];
}
