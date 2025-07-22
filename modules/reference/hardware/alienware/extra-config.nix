# Copyright 2025 TII (SSRC) and the Ghaf contributors
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
      # Make sure to use the correct Bus ID values for your system
      # TODO: Need to investigate does prime really uses mentioned Ids here?
      # Hardcoded to what is enumerated in guivm, values may change in future
      nvidiaBusId = "PCI:14:0:0";
      intelBusId = "PCI:13:0:0";
    };
  };

  microvm.qemu.extraArgs =
    [
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
