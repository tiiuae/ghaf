# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# mkCommonHostBindings - Creates common host bindings module for all VMs
#
# This function generates a NixOS module containing configuration that is
# shared across ALL VMs. It reads values directly from the host config,
# so callers only need to provide VM-specific values (vmName, tpmIndex).
#
# Usage:
#   commonHostBindings = mkCommonHostBindings hostConfig {
#     vmName = "net-vm";
#     tpmIndex = "0x81704000";
#   };
#
#   vmConfig = baseVm.extendModules { modules = [ commonHostBindings ]; };
#
# The function reads from hostConfig:
#   - config.ghaf.networking.hosts.${vmName}.cid (vsock CID)
#   - config.ghaf.virtualization.microvm.storeOnDisk
#   - config.ghaf.virtualization.storagevm-encryption.enable
#   - config.ghaf.logging.listener.address
#   - config.ghaf.logging.server.endpoint
#   - config.nixpkgs.buildPlatform.system
#   - config.nixpkgs.hostPlatform.system
#
hostConfig:
{
  # VM name (e.g., "net-vm", "gui-vm")
  vmName,
  # TPM NV index (unique per VM for storage encryption)
  tpmIndex,
}:
let
  # Extract all values from host config - SINGLE SOURCE OF TRUTH
  vmCid = hostConfig.ghaf.networking.hosts.${vmName}.cid or 3;
  inherit (hostConfig.ghaf.virtualization.microvm) storeOnDisk;
  storageEncryptionEnable = hostConfig.ghaf.virtualization.storagevm-encryption.enable;
  loggingListenerAddress = hostConfig.ghaf.logging.listener.address or "";
  loggingServerEndpoint = hostConfig.ghaf.logging.server.endpoint or "";
  buildPlatformSystem = hostConfig.nixpkgs.buildPlatform.system;
  hostPlatformSystem = hostConfig.nixpkgs.hostPlatform.system;
in
# Returns a NixOS module
{
  lib,
  ...
}:
{
  # === Logging Configuration ===
  # Pass logging settings from host to VM
  ghaf.logging = {
    listener.address = loggingListenerAddress;
    server.endpoint = loggingServerEndpoint;
  };

  # === Platform Configuration ===
  # Ensure VM uses correct platform settings (critical for cross-compilation)
  nixpkgs = {
    buildPlatform.system = buildPlatformSystem;
    hostPlatform.system = hostPlatformSystem;
  };

  # === Storage Encryption ===
  ghaf.storagevm.encryption.enable = storageEncryptionEnable;

  # === TPM Passthrough ===
  # Each VM gets a unique TPM NV index for isolated key storage
  ghaf.virtualization.microvm.tpm.passthrough = {
    enable = storageEncryptionEnable;
    rootNVIndex = tpmIndex;
  };

  # === Microvm Configuration ===
  microvm = {
    # Nix store shares - only when not using storeOnDisk
    shares = lib.optionals (!storeOnDisk) [
      {
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
        proto = "virtiofs";
      }
    ];

    # Writable store overlay for non-storeOnDisk mode
    writableStoreOverlay = lib.mkIf (!storeOnDisk) "/nix/.rw-store";

    # Vsock device for inter-VM communication
    qemu.extraArgs = [
      "-device"
      "vhost-vsock-pci,guest-cid=${toString vmCid}"
    ];

    # QEMU machine type based on architecture
    qemu.machine =
      {
        x86_64-linux = "q35";
        aarch64-linux = "virt";
      }
      .${hostPlatformSystem} or "q35";
  }
  // lib.optionalAttrs storeOnDisk {
    # Store-on-disk mode configuration
    storeOnDisk = true;
    storeDiskType = "erofs";
    storeDiskErofsFlags = [
      "-zlz4hc"
      "-Eztailpacking"
    ];
  };
}
