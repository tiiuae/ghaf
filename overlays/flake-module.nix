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
    crosvm-ghaf = crosvmGhaf;
    crosvm =
      final: prev:
      inputs.nixpkgs.lib.optionalAttrs prev.stdenv.hostPlatform.isx86_64 (crosvmGhaf final prev);

    ghaf-device-manager = inputs.ghaf-device-manager.overlays.default;

    # Carry the two focused logging fixes from ghafpkgs#362 until it merges,
    # while retaining the authoritative tiiuae/ghafpkgs input.
    ghafpkgs-crosvm-fixes = _final: prev: {
      ghaf-mem-manager = prev.ghaf-mem-manager.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./patches/ghaf-mem-manager-no-syslog.patch ];
      });
      ghaf-usb-applet = prev.ghaf-usb-applet.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./patches/ghaf-usb-applet-log-level.patch ];
      });
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
      inputs.self.overlays.ghafpkgs-crosvm-fixes
      inputs.ctrl-panel.overlays.default
      inputs.givc.overlays.default
      inputs.gp-gui.overlays.default
      inputs.wireguard-gui.overlays.default
      inputs.vhotplug.overlays.default
    ];
  };
}
