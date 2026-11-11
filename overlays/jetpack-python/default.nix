# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Python fixes needed only to build jetpack-nixos' UEFI/EDK2 firmware.
#
# Apply only to the Python 3.12 interpreter used by stuart.nix. Applying even
# test-only overrides to the image's default Python changes SCons dependencies,
# then PipeWire, GTK and Chromium, losing their binary-cache matches.
# The Jetpack module keeps this overlay out of non-Jetson targets.
(_final: prev: {
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (
      pythonFinal: pythonPrev:
      prev.lib.optionalAttrs (pythonPrev.pythonAtLeast "3.12" && pythonPrev.pythonOlder "3.13") (
        prev.lib.composeManyExtensions [
          (import ./setuptools-pkg-resources)
          (import ./threadpoolctl-no-check)
          (import ./typer-file-error)
        ] pythonFinal pythonPrev
      )
    )
  ];
})
