# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
_pyFinal: pyPrev: {
  # Fix build error with python 3.14:
  #   importlib.metadata.PackageNotFoundError: No package metadata was found for uefi-firmware-parser
  # Set dontCheckPythonMetadata to skip the pythonMetadataCheckPhase.
  # The nested overrides are needed to reach inside the uefi-firmware-parser derivation.
  patchfv = pyPrev.patchfv.override (prevArgs: {
    python3Packages = prevArgs.python3Packages // {
      buildPythonPackage =
        args: prevArgs.python3Packages.buildPythonPackage (args // { dontCheckPythonMetadata = true; });
    };
  });
}
