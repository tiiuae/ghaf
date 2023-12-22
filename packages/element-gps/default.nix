# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{python3Packages}:
with python3Packages;
  buildPythonApplication {
    pname = "gpswebsock";
    version = "1.0";

    propagatedBuildInputs = [websockets];

    src = ./.;
  }
