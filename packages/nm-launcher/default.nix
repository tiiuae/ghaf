# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  networkmanagerapplet,
  writeShellApplication,
  lib,
  ...
}:
writeShellApplication {
  name = "nm-launcher";

  text = ''
    export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/dbusproxy_net.sock
    ${networkmanagerapplet}/bin/nm-applet --indicator
  '';

  meta = {
    description = "Script to launch nm-connection-editor to configure network of netvm using D-Bus via GIVC.";
    platforms = lib.platforms.linux;
  };
}
