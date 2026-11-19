# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# ghaf's integration to jetpack-nixos
#
{ ... }:
{
  imports = [
    ./profiles
    ./nvidia-jetson-orin
    ./nx-netvm-ethernet-pci-passthrough.nix
    ./agx-netvm-wlan-pci-passthrough.nix
  ];

  # NVIDIA's L4T udev rules give the GPU debug/profiling nodes to a "debug" group
  # (nvhost-dbg-gpu, nvhost-prof-gpu, nvhost-ctxsw-gpu and friends, in
  # *-tegra-devices.rules). The rules ship inside the L4T payload rather than as
  # jetpack-nixos source, and nothing declares the group, so udev logs
  #
  #   Failed to resolve group 'debug', ignoring: Unknown group
  #
  users.groups.debug = { };
}
