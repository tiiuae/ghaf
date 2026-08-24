# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Display-only peer for the compute gpu-vm.
{ lib, ... }:
{
  _file = ./default.nix;

  imports = [ (import ../payload/host-module.nix { role = "dispvm"; }) ];

  options.ghaf.hardware.nvidia.passthroughs.disp_vm.enable =
    lib.mkEnableOption "Tegra234 display passthrough to disp-vm on NVIDIA Orin";
}
