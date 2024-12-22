# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay patches packages in nixpkgs, and adds in some of the ghaf's
# packages.
#
(final: prev: {
  gala-app = final.callPackage ../../packages/gala { };
  element-desktop = import ./element-desktop { inherit prev; };
  element-gps = final.callPackage ../../packages/element-gps { };
  element-web = final.callPackage ../../packages/element-web { };
  waypipe = import ./waypipe { inherit final prev; };
  qemu_kvm = import ./qemu { inherit final prev; };
  bt-launcher = final.callPackage ../../packages/bt-launcher { };
  labwc = import ./labwc { inherit prev; };
  tpm2-pkcs11 = import ./tpm2-pkcs11 { inherit prev; };
  mitmweb-ui = final.callPackage ../../packages/mitmweb-ui { };
  open-normal-extension = final.callPackage ../../packages/open-normal-extension { };
  hardware-scan = final.callPackage ../../packages/hardware-scan { };
  globalprotect-openconnect =
    final.libsForQt5.callPackage ../../packages/globalprotect-openconnect
      { };
  gtklock-userinfo-module = import ./gtklock-userinfo-module { inherit prev; };
  gtklock = import ./gtklock { inherit prev; };
})
