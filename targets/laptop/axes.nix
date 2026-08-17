# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Feature axes. A machine listing N axes yields 2^N targets, one per subset;
# the name gains each selected suffix in declaration order.
#
#   config    merged into extraConfig (under `ghaf.`)
#   vmConfig  merged into the builder's vmConfig
let
  budgets = import ../../modules/reference/hardware/vm-budgets.nix;
in
{
  low-mem = {
    suffix = "-low-mem";
    vmConfig = budgets.low;
  };

  storeDisk = {
    suffix = "-storeDisk";
    config.virtualization.microvm.storeOnDisk.enable = true;
  };
}
