# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay patches packages in nixpkgs, and adds in some of the ghaf's
# packages.
#
/*
{ final, prev, builtins}:
let
  # Import and evaluate the QEMU overlays
  qemuOverlay1 = import ./qemu { inherit final prev; };
  qemuOverlay2 = import ../../modules/jetpack/nvidia-jetson-orin/virtualization/host/gpio-virt-host/overlays/qemu { inherit final prev; };

  # Merge the resulting attribute sets
  # mergedQemu = builtins.mergeAttrs qemuOverlay1 qemuOverlay2;
in
*/
(final: prev: {
  gala-app = final.callPackage ../../packages/gala { };
  element-desktop = import ./element-desktop { inherit prev; };
  element-gps = final.callPackage ../../packages/element-gps { };
  element-web = final.callPackage ../../packages/element-web { };
  waypipe = import ./waypipe { inherit final prev; };
  # qemu_kvm = import ./qemu { inherit final prev; };
  # we have to patch qemu_kvm directly ... for now
  # qemu_kvm = builtins.mergeAttrs qemuOverlay1 qemuOverlay2;
  qemu_kvm = import ./qemu/gpio-passthrough-qemu-9.nix { inherit final prev; };
  nm-launcher = final.callPackage ../../packages/nm-launcher { };
  icon-pack = final.callPackage ../../packages/icon-pack { };
  labwc = import ./labwc { inherit prev; };
  tpm2-pkcs11 = import ./tpm2-pkcs11 { inherit prev; };
  waybar = import ./waybar { inherit prev; };
  mitmweb-ui = final.callPackage ../../packages/mitmweb-ui { };
  gtklock = import ./gtklock { inherit prev; };
  hardware-scan = final.callPackage ../../packages/hardware-scan { };
})
