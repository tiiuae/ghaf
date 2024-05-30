# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay patches packages in nixpkgs, and adds in some of the ghaf's
# packages.
#
(final: prev: {
  gala-app = final.callPackage ../../packages/gala {};
  element-desktop = import ./element-desktop {inherit prev;};
  element-gps = final.callPackage ../../packages/element-gps {};
  element-web = final.callPackage ../../packages/element-web {};
  waypipe = import ./waypipe {inherit final prev;};
  wifi-connector = final.callPackage ../../packages/wifi-connector {};
  wifi-connector-nmcli = final.callPackage ../../packages/wifi-connector {useNmcli = true;};
  qemu_kvm = import ./qemu {inherit final prev;};
  nm-launcher = final.callPackage ../../packages/nm-launcher {};
  icon-pack = final.callPackage ../../packages/icon-pack {};
  ghaf-openbox-theme = final.callPackage ../../packages/ghaf-openbox-theme {};
  labwc = import ./labwc {inherit prev;};
  tpm2-pkcs11 = import ./tpm2-pkcs11 {inherit prev;};
  waybar = import ./waybar {inherit prev;};
  mitmweb-ui = final.callPackage ../../packages/mitmweb-ui {};
})
