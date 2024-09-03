# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ python3Packages, fetchFromGitHub }:
python3Packages.buildPythonApplication rec {
  pname = "kernel-hardening-checker";
  version = "0.6.1-git${src.rev}";

  src = fetchFromGitHub {
    owner = "a13xp0p0v";
    repo = "kernel-hardening-checker";
    rev = "cce3be96474ddb0e1e59b1b5e5b539c5e99c054b";
    sha256 = "sha256-b+k2BSNF9Lc4WQnH7bYg87BEKLY2aSQ6a768SWT6w+Y=";
  };
}
