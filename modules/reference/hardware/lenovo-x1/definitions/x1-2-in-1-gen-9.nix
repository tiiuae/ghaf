# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  # System name
  name = "LENOVO ThinkPad X1 2-in-1 Gen 9";

  # List of system SKUs covered by this configuration
  skus = [
    "LENOVO_MT_21KE_BU_Think_FM_ThinkPad X1 2-in-1 Gen 9 21KE0056GR"
  ];

  # Host configuration
  host = {
    kernelConfig.kernelParams = [
      "intel_iommu=on,sm_on"
      "iommu=pt"
      "acpi_backlight=vendor"
      "acpi_osi=linux"
      #"module_blacklist=i2c_i801,i915,iwlwifi,snd_hda_intel,snd_sof_pci_intel_mtl,spi_intel_pci,xe"
      "module_blacklist=i915,xe,snd_pcm" # Prevent i915,xe,snd_pcm modules from being accidentally used by host
    ];
  };

  # Input devices
  input = {
    misc = {
      name = [
        # "AT Translated Set 2 keyboard" "Intel HID events" "sof-hda-dsp Mic" "sof-hda-dsp Headphone" "sof-hda-dsp HDMI/DP,pcm=3" "sof-hda-dsp HDMI/DP,pcm=4" "sof-hda-dsp HDMI/DP,pcm=5" "Sleep Button" "Lid Switch" "Power Button" "ThinkPad Extra Buttons" "Video Bus"
        "ThinkPad Extra Buttons"
      ];
      evdev = [
        # /dev/input/by-path/platform-i8042-serio-0-event-kbd /dev/input/by-path/platform-INTC1070:00-event /dev/input/by-path/pci-0000:00:1f.3-platform-skl_hda_dsp_generic-event /dev/input/by-path/platform-thinkpad_acpi-event
        "/dev/input/by-path/platform-thinkpad_acpi-event"
      ];
    };
  };

  # Network devices for passthrough to netvm
  network.pciDevices = [
    {
      # Network controller: Intel Corporation Meteor Lake PCH CNVi WiFi (rev 20)
      name = "wlp0s5f1";
      path = "0000:00:14.3";
      vendorId = "8086";
      productId = "7e40";
    }
  ];

  # GPU devices for passthrough to guivm
  gpu = {
    pciDevices = [
      {
        # VGA compatible controller: Intel Corporation Meteor Lake-P [Intel Graphics] (rev 08)
        path = "0000:00:02.0";
        vendorId = "8086";
        productId = "7d45";
        # opregion is required for type-c display to work
        qemu.deviceExtraArgs = "x-igd-opregion=on";
      }
    ];
    kernelConfig = {
      # Kernel modules are indicative only, please investigate with lsmod/modinfo
      stage1.kernelModules = [
        "i915"
        "xe"
      ];
      stage2.kernelModules = [ ];
      kernelParams = [
        "earlykms"
      ];
    };
  };

  # Audio device for passthrough to audiovm
  audio = {
    # Force a PCI device reset to the audio device
    # This is to get the pci hardware device to the default state at shutdown
    removePciDevice = "0000:00:1f.3";

    pciDevices = [
      {
        # ISA bridge: Intel Corporation Device 7e03 (rev 20)
        path = "0000:00:1f.0";
        vendorId = "8086";
        productId = "7e03";
      }
      {
        # Serial bus controller: Intel Corporation Meteor Lake-P SPI Controller (rev 20)
        path = "0000:00:1f.5";
        vendorId = "8086";
        productId = "7e23";
      }
      {
        # Audio device: Intel Corporation Meteor Lake-P HD Audio Controller (rev 20)
        path = "0000:00:1f.3";
        vendorId = "8086";
        productId = "7e28";
      }
      {
        # SMBus: Intel Corporation Meteor Lake-P SMBus Controller (rev 20)
        path = "0000:00:1f.4";
        vendorId = "8086";
        productId = "7e22";
      }
    ];
    kernelConfig = {
      # Kernel modules are indicative only, please investigate with lsmod/modinfo
      stage1.kernelModules = [ ];
      stage2.kernelModules = [
        "i2c_i801"
        "snd_hda_intel"
        "snd_sof_pci_intel_mtl"
        "spi_intel_pci"
      ];
      kernelParams = [ "snd_intel_dspcfg.dsp_driver=0" ];
    };
  };

  # USB devices for passthrough
  usb.deviceList = [
    # Integrated Camera
    {
      vms = [ "business-vm" ];
      name = "cam0";
      hostbus = "3";
      hostport = "9";
    }
  ];
}
