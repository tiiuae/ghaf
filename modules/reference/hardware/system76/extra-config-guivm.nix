# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  # Daemons run on the host; the GUI VM only needs the modules.
  hardware.system76 = {
    power-daemon.enable = false;
    kernel-modules.enable = true;
    firmware-daemon.enable = false;
  };
}
