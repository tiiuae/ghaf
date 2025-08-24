# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  buildPythonApplication,
  pyudev,
  setuptools,
}:
buildPythonApplication {
  pname = "vhwdetect";
  version = "0.1";
  pyproject = true;

  propagatedBuildInputs = [
    pyudev
  ];

  doCheck = false;

  build-system = [ setuptools ];

  src = ./vhwdetect;
}
