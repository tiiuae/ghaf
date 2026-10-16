# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Flake module for exporting overlays
{
  inputs,
  ...
}:
let
  crosvmGhaf = _final: prev: {
    # Backport the ARM64 DAX empty-entry fix for the pinned default guest kernel.
    linuxPackages = prev.linuxPackages.extend (
      _kernelFinal: kernelPrev: {
        kernel = kernelPrev.kernel.overrideAttrs (old: {
          patches = prev.lib.unique (
            (old.patches or [ ])
            ++ prev.lib.optionals (prev.lib.versions.majorMinor kernelPrev.kernel.version == "6.18") [
              ./linux-dax-empty-entry.patch
            ]
          );
        });
      }
    );
    crosvm = prev.crosvm.overrideAttrs (old: {
      src = inputs.ghaf-crosvm;
      patches = prev.lib.unique (
        (old.patches or [ ])
        ++ [
          ./crosvm-pmem-ext2-low-address.patch
          ./crosvm-dce-defer-thread.patch
          ./crosvm-arm64-readonly-cache-maintenance.patch
        ]
      );
      cargoDeps = prev.rustPlatform.fetchCargoVendor {
        src = inputs.ghaf-crosvm;
        hash = "sha256-I3XFmcXHo2isSTUZ27RkTH1OUp0UjOVXIGECoxcUzHU=";
      };
      cargoBuildFeatures = (old.cargoBuildFeatures or (old.buildFeatures or [ ])) ++ [
        "pci-hotplug"
        "power-monitor-sysfs"
        "vtpm"
      ];
      buildInputs = (old.buildInputs or [ ]) ++ [ prev.dbus ];
    });
  };
in
{
  flake.overlays = {
    cross-compilation = import ./cross-compilation;
    custom-packages = import ./custom-packages;
    crosvm-ghaf = crosvmGhaf;
    crosvm =
      final: prev:
      inputs.nixpkgs.lib.optionalAttrs prev.stdenv.hostPlatform.isx86_64 (crosvmGhaf final prev);

    ghaf-device-manager = inputs.ghaf-device-manager.overlays.default;

    # Jetson-only Python fixes for the EDK2/UEFI firmware build. Deliberately
    # excluded from `default`: it rewrites pythonPackagesExtensions globally.
    # Applied by modules/reference/hardware/jetpack/default.nix.
    jetpack-python = import ./jetpack-python;

    # Jetson-only build fix for the L4T OOT modules against kernels >= 6.12.97.
    # Also applied by modules/reference/hardware/jetpack/default.nix.
    jetpack-nvdisplay = import ./jetpack-nvdisplay;

    # This is a composition of all the overlays that are used in the project
    # and is used to export a simple default interface.
    default = inputs.nixpkgs.lib.composeManyExtensions [
      #internal overlays
      inputs.self.overlays.own-pkgs-overlay
      inputs.self.overlays.custom-packages
      inputs.self.overlays.crosvm
      inputs.self.overlays.ghaf-device-manager
      #external overlays that we use
      inputs.ghafpkgs.overlays.default
      inputs.ctrl-panel.overlays.default
      inputs.givc.overlays.default
      (_final: prev: {
        ota-update = prev.ota-update.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [ ./ota-update-require-esp.patch ];
        });
      })
      inputs.gp-gui.overlays.default
      inputs.wireguard-gui.overlays.default
      inputs.vhotplug.overlays.default
    ];
  };
}
