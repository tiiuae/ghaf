# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, ... }:
{
  _file = ./dce-probe-host.nix;

  hardware.nvidia-jetpack.virtualization.dceHost.enable = true;

  # The display is owned by a guest when the host-side DCE proxy is enabled.
  ghaf.profiles.graphics.enable = lib.mkForce false;
}
