# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  python3Packages,
}:
python3Packages.buildPythonApplication {
  pname = "gpswebsock";
  version = "1.0";

  propagatedBuildInputs = [ python3Packages.websockets ];

  src = ./.;
  meta = {
    description = "Point-to-point messaging server for Matrix";
    platforms = lib.platforms.linux;
  };
}
