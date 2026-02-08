# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# GUI VM Shared Memory Feature Module
#
# This module configures kernel parameters for kvm_ivshmem shared memory
# communication between VMs.
#
# This module is auto-included when ghaf.virtualization.microvm.sharedMem.enable is true.
#
{
  lib,
  globalConfig,
  ...
}:
let
  # Only enable if shared memory is enabled in globalConfig
  sharedMemEnabled = globalConfig.virtualization.microvm.sharedMem.enable or false;
  flataddr = globalConfig.virtualization.microvm.sharedMem.flataddr or "0x220000000";
in
{
  _file = ./shared-mem.nix;

  config = lib.mkIf sharedMemEnabled {
    # Configure kernel parameters for kvm_ivshmem
    boot.kernelParams = [
      "kvm_ivshmem.flataddr=${flataddr}"
    ];
  };
}
