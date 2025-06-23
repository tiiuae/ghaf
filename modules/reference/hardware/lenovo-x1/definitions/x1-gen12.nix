# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  # System name
  name = "Lenovo X1 Carbon Gen 12";

  # List of system SKUs covered by this configuration
  skus = [
    "LENOVO_MT_21KC_BU_Think_FM_ThinkPad X1 Carbon Gen 12 21KC006CMX"
    # TODO Add more SKUs
  ];

  host = {
    kernelConfig.kernelParams = [
      "intel_iommu=on,sm_on"
      "iommu=pt"
      "module_blacklist=i915,xe,snd_pcm,mei_me" # Prevent kernel modules from being accidentally used by host
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
      # Network controller [0280]: Intel Corporation Meteor Lake PCH CNVi WiFi [8086:7e40](rev 20)
      # iwlwifi
      path = "0000:00:14.3";
      vendorId = "8086";
      productId = "7e40";
      name = "wlp0s5f0";
    }
  ];

  gpu = {
    pciDevices = [
      {
        # VGA compatible controller [0300]: Intel Corporation Meteor Lake-P [Intel Graphics] [8086:7d45] (rev 08)
        # i915,xe
        path = "0000:00:02.0";
        vendorId = "8086";
        productId = "7d45";
        qemu.deviceExtraArgs = "x-igd-opregion=on";
      }
      {
        # Communication controller [0780]: Intel Corporation Device [8086:7e70] (rev 20)
        # mei_me (DDC/HDCP/EDID)
        path = "0000:00:16.0";
        vendorId = "8086";
        productId = "7e70";
      }
    ];
    kernelConfig = {
      stage1.kernelModules = [
        "i915"
        "xe"
      ];
      kernelParams = [
        "earlykms"
      ];
    };
  };

  # With the current implementation, the whole PCI IOMMU group 14:
  #   00:1f.x in the example from Lenovo X1 Carbon
  #   must be defined for passthrough to AudioVM
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
        # Audio device: Intel Corporation Meteor Lake-P HD Audio Controller (rev 20) (prog-if 80)
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
      {
        # Serial bus controller: Intel Corporation Meteor Lake-P SPI Controller (rev 20)
        path = "0000:00:1f.5";
        vendorId = "8086";
        productId = "7e23";
      }
    ];
    kernelConfig.kernelParams = [ "snd_intel_dspcfg.dsp_driver=0" ];
  };

  usb.deviceList = [
    {
      # Integrated camera
      vms = [
        "business-vm"
      ];
      name = "cam0";
      hostbus = "3";
      hostport = "9";
    }
    # Fingerprint reader
    {
      vms = [ "gui-vm" ];
      name = "fpr0";
      hostbus = "3";
      hostport = "7";
    }
    # Bluetooth controller
    {
      vms = [ "audio-vm" ];
      name = "bt0";
      hostbus = "3";
      hostport = "10";
    }
  ];
}
