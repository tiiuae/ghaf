# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ python3, writeScriptBin }:
writeScriptBin "ghaf-verify-enrollment" (
  "#!${python3}/bin/python3\n" + builtins.readFile ./verify-enrollment.py
)
