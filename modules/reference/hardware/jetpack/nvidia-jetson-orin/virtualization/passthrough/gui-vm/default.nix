# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# Combined GPU, media, and display passthrough to gui-vm.
{ lib, ... }:
{
  _file = ./default.nix;

  imports = [ (import ../payload/host-module.nix { role = "guivm"; }) ];

  options.ghaf.hardware.nvidia.passthroughs.gui_vm.enable =
    lib.mkEnableOption "Tegra234 GPU, engine, and display passthrough to gui-vm on NVIDIA Orin";
}
