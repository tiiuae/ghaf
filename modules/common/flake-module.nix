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
      ./nix.nix
      ./security
      ./services
      ./storage-persistence.nix
      ./systemd
      ./time
      ./users
      ./version
      ./virtualization
      # keep-sorted end

      # Pin `nixpkgs` for nixPath/registry on debug builds only.
      #
      # The value is the nixpkgs *source*: ~480 MB unpacked, a ~200 MB closure,
      # and pinning it in nixPath/registry makes it a real runtime dependency, so
      # it is copied into the image. Useful on a debug image where `nix repl` and
      # `nix-shell` should resolve against the pinned tree; pure bloat on a
      # release one.
      #
      #
      # This is the raw nixpkgs input, not ghaf's overlaid package set, and it
      # cannot be otherwise: nixPath and the registry take a path to a nixpkgs
      # *source tree*, while overlays are applied at import time and are not part
      # of any source. So `nix repl`/`nix-shell` on a debug device resolve against
      # stock nixpkgs, not against what the image was built from -- packages
      # instantiated that way will not share store paths with the system.
      #
      # Making them agree would mean shipping a small flake that imports nixpkgs
      # with `inputs.self.overlays.default` and pinning *that*, which is a real
      # design change rather than a one-line fix.
      (
        { config, lib, ... }:
        {
          ghaf.nix.nixpkgs = lib.mkIf config.ghaf.profiles.debug.enable inputs.nixpkgs;
        }
      )
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
