# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Flake module for exporting overlays
{
  inputs,
  ...
}:
{
  flake.overlays = {
    cross-compilation = import ./cross-compilation;
    custom-packages = import ./custom-packages;
    crosvm = _final: prev: {
      crosvm = prev.crosvm.overrideAttrs (old: {
        src = inputs.ghaf-crosvm;
        cargoDeps = prev.rustPlatform.fetchCargoVendor {
          src = inputs.ghaf-crosvm;
          hash = "sha256-lU30pTzJ1hYyHcpFKemZou9d2ZqSlFu4JC+IUe2Gm5A=";
        };
        cargoBuildFeatures = (old.cargoBuildFeatures or (old.buildFeatures or [ ])) ++ [
          "pci-hotplug"
          "power-monitor-sysfs"
          "vtpm"
        ];
        buildInputs = (old.buildInputs or [ ]) ++ [ prev.dbus ];
      });
    };

    ghaf-device-manager = _final: prev: {
      ghaf-device-manager =
        inputs.ghaf-device-manager.packages.${prev.stdenv.hostPlatform.system}.default;
    };

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
      inputs.gp-gui.overlays.default
      inputs.wireguard-gui.overlays.default
      inputs.vhotplug.overlays.default
    ];
  };
}
