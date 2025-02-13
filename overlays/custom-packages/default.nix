# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay patches packages in nixpkgs, and adds in some of the ghaf's
# packages.
#
(final: prev: {
  element-desktop = import ./element-desktop { inherit prev; };
  gtklock = import ./gtklock { inherit prev; };
  labwc = import ./labwc { inherit prev; };
  qemu_kvm = import ./qemu { inherit final prev; };
  tpm2-pkcs11 = import ./tpm2-pkcs11 { inherit prev; };
  papirus-icon-theme = import ./papirus-icon-theme { inherit prev; };
  libfm = import ./libfm { inherit prev; };
  wireguard-gui = final.callPackage ../../packages/wireguard-gui {};
  wireguard-gui-launcher = final.callPackage ../../packages/wireguard-gui-launcher {};
})
