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
  nixpkgs.overlays = [ self.overlays.jetpack-python ];
}
