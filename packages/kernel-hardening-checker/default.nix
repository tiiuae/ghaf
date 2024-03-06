# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  python3Packages,
  inputs,
}:
python3Packages.buildPythonApplication rec {
  pname = "kernel-hardening-checker";
  version = "0.6.1-git${src.rev}";
  src = inputs.kernel-hardening-checker;
}
