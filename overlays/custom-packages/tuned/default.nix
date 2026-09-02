# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev }:
prev.tuned.overrideAttrs (old: {
  # Neither is actually imported by tuned's code (pyperf's "perf" module is
  # unrelated to the kernel's tools/perf bindings tuned optionally imports).
  propagatedBuildInputs = builtins.filter (
    p:
    !(builtins.elem (p.pname or "") [
      "tuna"
      "pyperf"
    ])
  ) old.propagatedBuildInputs;
})
