# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  python3Packages,
  fetchPypi,
  lib,
}:
python3Packages.buildPythonPackage rec {
  pname = "qemu.qmp";
  version = "0.0.3";

  src = fetchPypi {
    inherit pname version;
    sha256 = "sha256-y8iPvMEV7pQ9hER9FyxkLaEgIgRRQWwvYhrPM98eEBA=";
  };

  pyproject = true;

  nativeBuildInputs = [
    python3Packages.setuptools-scm
  ];

  meta = {
    homepage = "https://www.qemu.org/";
    description = "QEMU Monitor Protocol library";
    license = lib.licenses.lgpl2Plus;
  };
}
