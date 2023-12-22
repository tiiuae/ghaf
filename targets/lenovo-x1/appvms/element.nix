# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{pkgs, ...}: {
  name = "element";
  packages = [pkgs.element-desktop pkgs.element-gps pkgs.gpsd];
  #packages = [pkgs.element-desktop pkgs.gpsd pkgs.element-gps];
  macAddress = "02:00:00:03:08:01";
  ramMb = 4096;
  cores = 1;
  extraModules = [
    {
      services.gpsd = {
        enable = true;
        devices = ["/dev/ttyUSB0"];
        readonly = true;
        debugLevel = 2;
        listenany = true;
        extraArgs = ["-n"]; # Do not wait for a client to connect before polling
      };

      systemd.services.element-gps = {
        description = "Element-gps is a GPS location provider for Element websocket interface.";
        enable = true;
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.element-gps}/bin/main.py";
          Restart = "on-failure";
          RestartSec = "2";
        };
        wantedBy = ["multi-user.target"];
      };

      time.timeZone = "Asia/Dubai";

      microvm.qemu.extraArgs = [
        # Lenovo X1 integrated usb webcam
        "-device"
        "qemu-xhci"
        "-device"
        "usb-host,vendorid=0x04f2,productid=0xb751"
        # External USB GPS receiver
        "-device"
        "usb-host,vendorid=0x067b,productid=0x23a3"
        # Connect sound device to hosts pulseaudio socket
        "-audiodev"
        "pa,id=pa1,server=unix:/run/pulse/native"
        # Add HDA sound device to guest
        "-device"
        "intel-hda"
        "-device"
        "hda-duplex,audiodev=pa1"
      ];
    }
  ];
}
