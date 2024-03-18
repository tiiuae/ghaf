# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  name = "Lenovo X1 Carbon Gen 11";

  mouse = [
    "ELAN067C:00 04F3:31F9 Mouse"
    "SYNA8016:00 06CB:CEB3 Mouse"
    "ELAN067B:00 04F3:31F8 Mouse"
  ];

  touchpad = [
    "ELAN067C:00 04F3:31F9 Touchpad"
    "SYNA8016:00 06CB:CEB3 Touchpad"
    "ELAN067B:00 04F3:31F8 Touchpad"
  ];

  disks = {
    disk1.device = "/dev/nvme0n1";
  };

  network.pciDevices = [
    {
      # Passthrough Intel WiFi card
      path = "0000:00:14.3";
      vendorId = "8086";
      productId = "51f1";
      name = "wlp0s5f0";
    }
  ];

  gpu.pciDevices = [
    {
      # Passthrough Intel Iris GPU
      path = "0000:00:02.0";
      vendorId = "8086";
      productId = "a7a1";
    }
  ];
}
