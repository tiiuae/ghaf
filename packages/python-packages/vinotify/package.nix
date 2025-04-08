# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  buildPythonApplication,
  inotify-simple,
}:
buildPythonApplication {
  pname = "vinotify";
  version = "0.1";

  propagatedBuildInputs = [
    inotify-simple
  ];

  doCheck = false;

  src = ./vinotify;
}
