# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# ghaf's integration to jetpack-nixos
#
{ self, ... }:
{
  imports = [
    ./profiles
    ./nvidia-jetson-orin
    ./nx-netvm-ethernet-pci-passthrough.nix
    ./agx-netvm-wlan-pci-passthrough.nix
  ];

  # jetpack-nixos' EDK2/UEFI firmware build needs a setuptools that still ships
  # pkg_resources, and a relaxed chardet pin for pygount. Both act on
  # pythonPackagesExtensions, i.e. on every Python package in the instance, so
  # they are scoped to the Jetson targets rather than living in overlays.default
  # -- globally they break packages that need a newer setuptools (see
  # overlays/jetpack-python/default.nix).
  # jetpack-nvdisplay patches the R36.5 nvdisplay tree for the
  # pci_resize_resource() signature change in kernels >= 6.12.97.
  nixpkgs.overlays = [
    self.overlays.jetpack-python
    self.overlays.jetpack-nvdisplay
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
