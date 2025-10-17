# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  buildPythonApplication,
  websockets,
  setuptools,
}:
buildPythonApplication {
  pname = "gpswebsock";
  version = "1.0";
  pyproject = true;

  propagatedBuildInputs = [ websockets ];

  src = ./.;

  build-system = [ setuptools ];

  meta = {
    description = "Point-to-point messaging server for Matrix";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
