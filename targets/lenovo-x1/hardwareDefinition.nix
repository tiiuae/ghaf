# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  name = "Lenovo X1 Carbon";
  network.pciDevices = [
    # Passthrough Intel WiFi card 8086:51f1
    {
      path = "0000:00:14.3";
      vendorId = "8086";
      productId = "51f1";
      name = "wlp0s5f0";
    }
  ];
  gpu.pciDevices = [
    # Passthrough Intel Iris GPU 8086:a7a1
    {
      path = "0000:00:02.0";
      vendorId = "8086";
      productId = "a7a1";
    }
  ];
  virtioInputHostEvdevs = [
    # Lenovo X1 touchpad and keyboard
    "/dev/input/by-path/platform-i8042-serio-0-event-kbd"
    "/dev/mouse"
    "/dev/touchpad"
    # Lenovo X1 trackpoint (red button/joystick)
    "/dev/input/by-path/platform-i8042-serio-1-event-mouse"
  ];

  disks.disk1.device = "/dev/nvme0n1";
}
