# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
{
  ghaf.graphics.hybrid-setup = {
    enable = true;
    prime = {
      enable = true;
      forceNvidiaOffload = true;
    };
  };

  microvm.qemu.extraArgs = [
    "-drive"
    "file=${pkgs.OVMF.fd}/FV/OVMF_CODE.fd,if=pflash,unit=0,readonly=true"
    "-drive"
    "file=${pkgs.OVMF.fd}/FV/OVMF_VARS.fd,if=pflash,unit=1,readonly=true"
  ]
  ++ lib.optionals config.ghaf.services.brightness.enable [
    "-device"
    "virtio-serial"
    "-chardev"
    "socket,id=brightness,path=${config.ghaf.services.brightness.socketPath},server=on,wait=off"
    "-device"
    "virtserialport,chardev=brightness,name=brightness"
  ];
}
