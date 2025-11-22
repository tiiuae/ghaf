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

    # This is a composition of all the overlays that are used in the project
    # and is used to export a simple default interface.
    default = inputs.nixpkgs.lib.composeManyExtensions [
      #internal overlays
      inputs.self.overlays.own-pkgs-overlay
      inputs.self.overlays.custom-packages
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
