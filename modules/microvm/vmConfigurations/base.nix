# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Base VM Configuration - Layer 1
#
# This module provides the foundation for all Ghaf VMs.
# It is designed to be extended via lib.nixosSystem's extendModules.
#
# Note: This module receives `inputs` via specialArgs from the parent
# lib.nixosSystem call - no currying needed.
#
{
  lib,
  inputs,
  ...
}:
{
  imports = [
    inputs.preservation.nixosModules.preservation
    inputs.self.nixosModules.givc
    inputs.self.nixosModules.vm-modules
    inputs.self.nixosModules.profiles
  ];

  # Base VM configuration
  # These are sensible defaults that can be overridden by role modules

  ghaf = {
    # VM type identifier
    type = lib.mkDefault "system-vm";

    # Enable dynamic hostname export for VMs
    identity.vmHostNameExport.enable = lib.mkDefault true;
  };

  # State version - should match the NixOS release
  system.stateVersion = lib.mkDefault lib.trivial.release;

  # Minimal microvm defaults
  microvm = {
    # Optimize is disabled because when it is enabled, qemu is built without libusb
    optimize.enable = lib.mkDefault false;
    hypervisor = lib.mkDefault "qemu";
  };
}
