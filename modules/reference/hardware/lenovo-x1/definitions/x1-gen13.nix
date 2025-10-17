# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  # System name
  name = "LENOVO ThinkPad X1 Carbon Gen 13";

  # List of system SKUs covered by this configuration
  skus = [
    "LENOVO_MT_21NS_BU_Think_FM_ThinkPad X1 Carbon Gen 13 21NS0012US"
  ];

  # Host configuration
  host = {
    kernelConfig.kernelParams = [
      "intel_iommu=on,sm_on"
      "iommu=pt"
      "acpi_backlight=vendor"
      "acpi_osi=linux"
      "module_blacklist=i915,xesnd_hda_intel,snd_sof_pci_intel_lnl,spi_intel_pci,xe,bluetooth,btusb"
    ];
  };

  # Input devices
  input = {
    misc = {
      name = [
        # "AT Translated Set 2 keyboard" "Intel HID events" "sof-soundwire Headset Jack" "sof-soundwire HDMI/DP,pcm=5" "sof-soundwire HDMI/DP,pcm=6" "sof-soundwire HDMI/DP,pcm=7" "Sleep Button" "Lid Switch" "Power Button" "Video Bus"
        "ThinkPad Extra Buttons"
      ];
      evdev = [
        # /dev/input/by-path/platform-i8042-serio-0-event-kbd /dev/input/by-path/platform-INTC1070:00-event /dev/input/by-path/pci-0000:00:1f.3-platform-sof_sdw-event
        "/dev/input/by-path/platform-thinkpad_acpi-event"
      ];
    };
  };

  # Network devices for passthrough to netvm
  network.pciDevices = [
    {
      # Network controller: Intel Corporation BE201 320MHz (rev 10)
      name = "wlp0s5f0";
      path = "0000:00:14.3";
      vendorId = "8086";
      productId = "a840";
    }
  ];

  # GPU devices for passthrough to guivm
  gpu = {
    pciDevices = [
      {
        # VGA compatible controller: Intel Corporation Lunar Lake [Intel Arc Graphics 130V / 140V] (rev 04)
        path = "0000:00:02.0";
        vendorId = "8086";
        productId = "64a0";
      }
    ];
    kernelConfig = {
      # Kernel modules are indicative only, please investigate with lsmod/modinfo
      stage1.kernelModules = [
        "xe"
      ];
      kernelParams = [
        "earlykms"
      ];
    };
  };

  # Audio device for passthrough to audiovm
  audio = {
    pciDevices = [
      {
        # ISA bridge: Intel Corporation Device a807 (rev 10)
        path = "0000:00:1f.0";
        vendorId = "8086";
        productId = "a807";
      }
      {
        # Serial bus controller: Intel Corporation Lunar Lake-M SPI Controller (rev 10)
        path = "0000:00:1f.5";
        vendorId = "8086";
        productId = "a823";
      }
      {
        # Multimedia audio controller: Intel Corporation Lunar Lake-M HD Audio Controller (rev 10)
        path = "0000:00:1f.3";
        vendorId = "8086";
        productId = "a828";
      }
      {
        # SMBus: Intel Corporation Lunar Lake-M SMbus Controller (rev 10)
        path = "0000:00:1f.4";
        vendorId = "8086";
        productId = "a822";
      }
    ];
    kernelConfig = {
      # Kernel modules are indicative only, please investigate with lsmod/modinfo
      stage1.kernelModules = [ ];
      stage2.kernelModules = [
        "snd_hda_intel"
        "snd_sof_pci_intel_lnl"
        "spi_intel_pci"
      ];
      kernelParams = [ ];
    };
  };

  # USB devices for passthrough
  usb.devices = [
    # Integrated camera
    {
      name = "cam0";
      hostbus = "3";
      hostport = "4";
    }
  ];
}
