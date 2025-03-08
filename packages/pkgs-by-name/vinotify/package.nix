# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  python3Packages,
}:
python3Packages.buildPythonApplication rec {
  pname = "vinotify";
  version = "0.1";

  propagatedBuildInputs = [
    python3Packages.inotify-simple
  ];

  doCheck = false;

  src = ./vinotify;
}
