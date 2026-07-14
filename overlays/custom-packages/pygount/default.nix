# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# pygount 3.2.0 declares "chardet<6,>=5" but nixpkgs packages chardet
# 6.0.0.post1, which trips pythonRuntimeDepsCheckHook. Relax the pin until
# pygount (a build-time dependency of edk2-pytool-library, used by the
# Jetson EDK2/UEFI firmware build) is bumped upstream.
_pyFinal: pyPrev: {
  pygount = pyPrev.pygount.overridePythonAttrs (old: {
    pythonRelaxDeps = (old.pythonRelaxDeps or [ ]) ++ [ "chardet" ];
  });
}
