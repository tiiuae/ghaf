# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  ...
}:
{
  ghaf.graphics.hybrid-setup = {
    enable = true;
    prime.enable = true;
  };

  hardware.nvidia.nvidiaSettings = lib.mkForce false;
}
