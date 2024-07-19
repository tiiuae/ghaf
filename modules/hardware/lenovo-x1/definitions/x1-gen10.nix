# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  name = "Lenovo X1 Carbon Gen 10";

  host = {
    kernelConfig.kernelParams = [
      "intel_iommu=on,sm_on"
      "iommu=pt"
      "module_blacklist=i915" # Prevent i915 module from being accidentally used by host
      "acpi_backlight=vendor"
      "acpi_osi=linux"
    ];
  };

  input = {
    keyboard = {
      name = ["AT Translated Set 2 keyboard"];
      evdev = ["/dev/input/by-path/platform-i8042-serio-0-event-kbd"];
    };

    mouse = {
      name = [
        "ELAN067B:00 04F3:31F8 Mouse"
        "SYNA8016:00 06CB:CEB3 Mouse"
      ];
      evdev = [
        "/dev/mouse"
      ];
    };

    touchpad = {
      name = [
        "ELAN067B:00 04F3:31F8 Touchpad"
        "SYNA8016:00 06CB:CEB3 Touchpad"
      ];
      evdev = [
        "/dev/touchpad"
      ];
    };

    misc = {
      name = [
        "ThinkPad Extra Buttons"
        "TPPS/2 Elan TrackPoint"
      ];
      evdev = [
        "/dev/input/by-path/platform-i8042-serio-1-event-mouse"
        "/dev/input/by-path/platform-thinkpad_acpi-event"
      ];
    };
  };

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
      stage1.kernelModules = ["i915"];
      kernelParams = ["earlykms"];
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
    kernelConfig.kernelParams = [
      "snd_intel_dspcfg.dsp_driver=3"
      "snd_sof_intel_hda_common.dmic_num=4"
    ];
  };

  usb = {
    internal = [
      {
        name = "webcam";
        hostbus = "3";
        hostport = "8";
      }
      {
        name = "fprint-reader";
        hostbus = "3";
        hostport = "6";
      }
    ];
    external = [
      {
        name = "gps-device";
        vendorId = "067b";
        productId = "23a3";
      }
      {
        name = "yubikey";
        vendorId = "1050";
        productId = "0407";
      }
    ];
  };
}
