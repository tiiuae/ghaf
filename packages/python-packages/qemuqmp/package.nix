# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  buildPythonPackage,
  fetchPypi,
  lib,
  setuptools-scm,
}:
buildPythonPackage rec {
  pname = "qemu.qmp";
  version = "0.0.3";

  src = fetchPypi {
    inherit pname version;
    sha256 = "sha256-y8iPvMEV7pQ9hER9FyxkLaEgIgRRQWwvYhrPM98eEBA=";
  };

  pyproject = true;

  nativeBuildInputs = [ setuptools-scm ];

  meta = {
    homepage = "https://www.qemu.org/";
    description = "QEMU Monitor Protocol library";
    license = lib.licenses.lgpl2Plus;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
