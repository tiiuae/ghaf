# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Named VM memory budgets, in MB. Data only.
{
  # Machines with 16 GB or less. The guivm figure matches the current default and
  # is a pin, not a reduction; only the flatpak appvm actually shrinks (its mem is
  # multiplied by balloonRatio, so 5120 lands at 15360 against a default 18432).
  low = {
    sysvms.guivm.mem = 6144;
    appvms.flatpak.mem = 5120;
  };

  # Tablet-class units.
  minimal.sysvms = {
    guivm.mem = 2047;
    # Keep AudioVM at its QEMU-sized budget on tablet-class machines. The
    # Crosvm default uses 1024 MiB, which is too large for this constrained
    # profile.
    audiovm.mem = 512;
  };
}
