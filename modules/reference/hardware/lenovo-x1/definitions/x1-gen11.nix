# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  # System name
  name = "Lenovo X1 Carbon Gen 11";

  # List of system SKUs covered by this configuration
  skus = [
    "LENOVO_MT_21HM_BU_Think_FM_ThinkPad X1 Carbon Gen 11 21HM006EGR"
    "LENOVO_MT_21HM_BU_Think_FM_ThinkPad X1 Carbon Gen 11 21HM0072MX"
    # TODO Add more SKUs
  ];

  host = {
    kernelConfig.kernelParams = [
      "intel_iommu=on,sm_on"
      "iommu=pt"
      "module_blacklist=i915,xe,snd_pcm" # Prevent i915,xe,snd_pcm modules from being accidentally used by host
      "acpi_backlight=vendor"
      "acpi_osi=linux"
    ];
  };

  input = {
    keyboard = {
      name = [ "AT Translated Set 2 keyboard" ];
      evdev = [ "/dev/input/by-path/platform-i8042-serio-0-event-kbd" ];
    };

    mouse = {
      name = [
        [
          "ELAN067C:00 04F3:31F9 Mouse"
          "SYNA8016:00 06CB:CEB3 Mouse"
          "ELAN067B:00 04F3:31F8 Mouse"
          "SYNA8017:00 06CB:CEB2 Mouse"
        ]
        "TPPS/2 Elan TrackPoint"
      ];
      evdev = [
        "/dev/mouse0"
        "/dev/mouse1"
      ];
    };

    touchpad = {
      name = [
        [
          "ELAN067C:00 04F3:31F9 Touchpad"
          "SYNA8016:00 06CB:CEB3 Touchpad"
          "ELAN067B:00 04F3:31F8 Touchpad"
          "SYNA8017:00 06CB:CEB2 Touchpad"
          "ELAN901C:00 04F3:2C4E Touchpad"
        ]
      ];
      evdev = [ "/dev/touchpad0" ];
    };

    misc = {
      name = [ "ThinkPad Extra Buttons" ];
      evdev = [ "/dev/input/by-path/platform-thinkpad_acpi-event" ];
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
      productId = "51f1";
      name = "wlp0s5f0";
    }
  ];

  gpu = {
    pciDevices = [
      {
        # Passthrough Intel Iris GPU
        path = "0000:00:02.0";
        vendorId = "8086";
        productId = "a7a1";
      }
    ];
    kernelConfig = {
      stage1.kernelModules = [ "i915" ];
      kernelParams = [
        "earlykms"
        "i915.enable_dpcd_backlight=3"
      ];
    };
  };

  # With the current implementation, the whole PCI IOMMU group 14:
  #   00:1f.x in the example from Lenovo X1 Carbon
  #   must be defined for passthrough to AudioVM
  audio = {
    pciDevices = [
      {
        # ISA bridge: Intel Corporation Raptor Lake LPC/eSPI Controller (rev 01)
        path = "0000:00:1f.0";
        vendorId = "8086";
        productId = "519d";
      }
      {
        # Audio device: Intel Corporation Raptor Lake-P/U/H cAVS (rev 01)
        path = "0000:00:1f.3";
        vendorId = "8086";
        productId = "51ca";
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

  usb = {
    internal = [
      {
        name = "cam0";
        hostbus = "3";
        hostport = "8";
      }
      {
        name = "fpr0";
        hostbus = "3";
        hostport = "6";
      }
      {
        name = "bt0";
        hostbus = "3";
        hostport = "10";
      }
    ];
    external = [
      {
        name = "gps0";
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
