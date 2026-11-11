# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
  runCommand,
}:
let
  native = self.nixosConfigurations.nvidia-jetson-orin-nx-debug;
  cross = self.nixosConfigurations.nvidia-jetson-orin-nx-debug-from-x86_64;
  chromiumPaths =
    target:
    [ target.pkgs.chromium.drvPath ]
    ++ map (name: target.config.microvm.vms.${name}.evaluatedConfig.pkgs.chromium.drvPath) [
      "gui-vm"
      "chromium-vm"
    ];
  # An overlay changing a browser dependency must reach both build paths, even when
  # it means the public binary cache can no longer supply Chromium.
  withBrowserPatch =
    target:
    target.extendModules {
      modules = [
        {
          nixpkgs.overlays = [
            (_final: prev: {
              pipewire = prev.pipewire.overrideAttrs (old: {
                postPatch = (old.postPatch or "") + "\n# Browser overlay propagation test\n";
              });
            })
          ];
        }
      ];
    };
  patchedNative = (withBrowserPatch native).pkgs.chromium.drvPath;
  patchedCross = (withBrowserPatch cross).pkgs.chromium.drvPath;
in
assert lib.assertMsg (lib.all (path: path == native.pkgs.chromium.drvPath) (
  chromiumPaths native ++ chromiumPaths cross
)) "Native and cross Orin hosts and guests must use the same Chromium closure";
assert lib.assertMsg (
  patchedNative == patchedCross && patchedNative != native.pkgs.chromium.drvPath
) "Chromium dependency overlays must propagate equally to native and cross images";
runCommand "chromium-package-parity" { } "touch $out"
