# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  # System name
  name = "Lenovo X1 Carbon Gen 10";

  # List of system SKUs covered by this configuration
  skus = [
    # TODO Add SKUs
  ];

  host = {
    kernelConfig.kernelParams = [
      "intel_iommu=on,sm_on"
      "iommu=pt"
      "module_blacklist=i915,snd_pcm,bluetooth,btusb" # Prevent i915,snd_pcm module from being accidentally used by host
      "acpi_backlight=vendor"
      "acpi_osi=linux"
    ];
  };

  input = {
    misc = {
      name = [ "ThinkPad Extra Buttons" ];
      evdev = [ "/dev/input/by-path/platform-thinkpad_acpi-event" ];
    };
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

  gpu = {
    pciDevices = [
      {
        # Passthrough Intel Iris GPU
        path = "0000:00:02.0";
        vendorId = "8086";
        productId = "46a6";
      }
    ];
    kernelConfig = {
      stage1.kernelModules = [ "i915" ];
      kernelParams = [ "earlykms" ];
    };
  };

  # With the current implementation, the whole PCI IOMMU group 13:
  #   00:1f.x in the Lenovo X1 Carbon 10 gen
  #   must be defined for passthrough to AudioVM
  audio = {
    pciDevices = [
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
    kernelConfig.kernelParams = [ "snd_intel_dspcfg.dsp_driver=0" ];
  };

  usb.devices = [
    # Integrated camera
    {
      name = "cam0";
      hostbus = "3";
      hostport = "8";
    }
    # Fingerprint reader
    {
      name = "fpr0";
      hostbus = "3";
      hostport = "6";
    }
    # Bluetooth controller
    {
      name = "bt0";
      hostbus = "3";
      hostport = "10";
    }
  ];
}
