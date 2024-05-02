# Copyright 2023-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{prev}:
# Ensure we are not building all the emulators in qemu
# we are only interested in the virtualization support
# TODO should we move this tp custom packages?
prev.qemu.override {
  hostCpuOnly = true;
}
