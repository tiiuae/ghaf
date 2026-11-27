# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Flake module for exporting overlays
{
  inputs,
  ...
}:
let
  crosvmPkg = _final: prev: {
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
in
{
  flake.overlays = {
    cross-compilation = import ./cross-compilation;
    custom-packages = import ./custom-packages;
    crosvm-ghaf = crosvmPkg;
    crosvm =
      final: prev:
      inputs.nixpkgs.lib.optionalAttrs prev.stdenv.hostPlatform.isx86_64 (crosvmPkg final prev);

    ghaf-device-manager = inputs.ghaf-device-manager.overlays.default;

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
      inputs.trayler.overlays.default
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
