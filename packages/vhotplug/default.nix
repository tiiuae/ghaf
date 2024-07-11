# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  python3Packages,
  pkgs,
  fetchFromGitHub,
}: let
  qemuqmp = pkgs.callPackage ../qemuqmp {};
in
  python3Packages.buildPythonApplication rec {
    pname = "vhotplug";
    version = "0.1";

    propagatedBuildInputs = [
      python3Packages.pyudev
      python3Packages.psutil
      qemuqmp
    ];

    doCheck = false;

    src = fetchFromGitHub {
      owner = "tiiuae";
      repo = "vhotplug";
      rev = "e65dc82409371ba217b8af583ed3bffdbd96a970";
      hash = "sha256-PH2RT865yl+SIojuNip8iHnhXPHxFtiRk2eQsqCvc8Q=";
    };
  }
