# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  name = "Lenovo X1 Carbon Gen 10";

  mouse = ["ELAN067B:00 04F3:31F8 Mouse" "SYNA8016:00 06CB:CEB3 Mouse"];
  touchpad = ["ELAN067B:00 04F3:31F8 Touchpad" "SYNA8016:00 06CB:CEB3 Touchpad"];

  disks = {
    disk1.device = "/dev/nvme0n1";
  };

  network.pciDevices = [
    {
      # Passthrough Intel WiFi card
      path = "0000:00:14.3";
      vendorId = "8086";
      productId = "51f0";
      name = "wlp0s5f0";
    }
  ];

  gpu.pciDevices = [
    {
      # Passthrough Intel Iris GPU
      path = "0000:00:02.0";
      vendorId = "8086";
      productId = "46a6";
    }
  ];

  # With the current implementation, the whole PCI IOMMU group 13:
  #   00:1f.x in the Lenovo X1 Carbon 10 gen
  #   must be defined for passthrough to AudioVM
  audio.pciDevices = [
    {
      # ISA bridge: Intel Corporation Alder Lake PCH eSPI Controller(rev 01)
      path = "0000:00:1f.0";
      vendorId = "8086";
      productId = "5182";
    }
    {
      # Audio device: Intel Corporation Alder Lake PCH-P High Definition Audio Controller (rev 01)
      path = "0000:00:1f.3";
      vendorId = "8086";
      productId = "51c8";
    }
    {
      # SMBus: Intel Corporation Alder Lake PCH-P SMBus Host Controller (rev 01)
      path = "0000:00:1f.4";
      vendorId = "8086";
      productId = "51a3";
    }
    {
      # Serial bus controller: Intel Corporation Alder Lake-P PCH SPI Controller (rev 01)
      path = "0000:00:1f.5";
      vendorId = "8086";
      productId = "51a4";
    }
  ];
}
