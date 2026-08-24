# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Common ghaf modules
#
{ inputs, ... }:
{
  _file = ./flake-module.nix;

  flake.nixosModules = {
    common.imports = [
      # keep-sorted start
      ./common.nix
      ./firewall
      ./global-config.nix
      ./identity
      ./logging
      ./networking
      ./security
      ./services
      ./storage-persistence.nix
      ./systemd
      ./time
      ./users
      ./version
      ./virtualization
      # keep-sorted end
    ];

    # Ghaf-patched QEMU package definition (ivshmem, TPM, USB, ACPI patches).
    # Imported by both host (via `common`) and VMs (via `vm-modules`).
    ghaf-qemu = ./virtualization/qemu.nix;

    # Imporeted as needed by targets that expect to dislpay a GUI of some sort.
    # Otherwise should be left out to reduce eval cost due to stylix's heavy overlays.
    theming = ./theming;

    # Cross-compilation module for building aarch64 targets from x86_64
    # This should be included via extendModules when generating
    # cross-compiled variants (e.g., -from-x86_64 builds).
    cross-compilation-from-x86_64 = {
      nixpkgs = {
        buildPlatform.system = "x86_64-linux";
        overlays = [ inputs.self.overlays.cross-compilation ];
      };
    };
  };
}
