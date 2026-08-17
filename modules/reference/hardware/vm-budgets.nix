# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Named VM memory budgets, in MB. Data only.
{
  # Machines with 16 GB or less.
  low = {
    sysvms.guivm.mem = 6144;
    appvms.flatpak.mem = 5120;
  };

  # Tablet-class units.
  minimal.sysvms.guivm.mem = 2047;
}
