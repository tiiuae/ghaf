# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  netvm,
  guivm,
}: {config, ...}: {
  microvm.host.enable = true;

  microvm.vms."${netvm}" = {
    flake = self;
    autostart = true;
  };

  microvm.vms."${guivm}" = {
    flake = self;
    autostart = true;
  };

  systemd.user.services."microvm@".environment = {XDG_RUNTIME_DIR="/run/user/1000"; WAYLAND_DISPLAY="wayland-1";};
  systemd.globalEnvironment = {XDG_RUNTIME_DIR="/run/user/1000";};
}
