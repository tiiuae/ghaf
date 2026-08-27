# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

import ./gpu-display-vm-base.nix {
  vmName = "gpu-vm";
  defaultMem = 6000;
}
