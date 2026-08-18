# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Feature axes. A machine listing N axes yields one target per subset; the name
# gains each selected suffix in declaration order. Axes sharing a `group` are
# mutually exclusive, so subsets naming two of them are never emitted.
#
#   suffix    appended to the target name
#   group     optional; at most one axis per group per target
#   config    merged into extraConfig (under `ghaf.`)
#   vmConfig  merged into the builder's vmConfig
let
  budgets = import ../../modules/reference/hardware/vm-budgets.nix;
in
{
  low-mem = {
    suffix = "-low-mem";
    group = "mem";
    vmConfig = budgets.low;
  };

  minimal-mem = {
    suffix = "-minimal-mem";
    group = "mem";
    vmConfig = budgets.minimal;
  };

  storeDisk = {
    suffix = "-storeDisk";
    config.virtualization.microvm.storeOnDisk.enable = true;
  };
}
