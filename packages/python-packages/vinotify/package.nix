# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  buildPythonApplication,
  inotify-simple,
  setuptools,
}:
buildPythonApplication {
  pname = "vinotify";
  version = "0.1";
  pyproject = true;

  propagatedBuildInputs = [
    inotify-simple
  ];

  doCheck = false;

  src = ./vinotify;
  build-system = [ setuptools ];
}
