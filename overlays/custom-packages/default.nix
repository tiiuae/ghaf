# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay customizes ghaf packages
#
{...}: {
  nixpkgs.overlays = [
    (import ./dbus-over-ssh)
    (import ./dbus-powercontrol)
    (import ./gala)
    (import ./systemd)
    (import ./waypipe)
    (import ./weston)
    (import ./wifi-connector)
    (import ./qemu)
  ];
}
