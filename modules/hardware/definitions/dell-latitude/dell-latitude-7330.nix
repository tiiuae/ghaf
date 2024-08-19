# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  # System name
  name = "Dell Inc. Not Specified";

  # List of system SKUs covered by this configuration
  skus = [ "0A9E Latitude 7330 Rugged Extreme" ];

  # Host configuration
  host = {
    kernelConfig.kernelParams = [
      "intel_iommu=on,sm_on"
      "iommu=pt"
      "acpi_backlight=vendor"
      "acpi_osi=linux"
      #"module_blacklist=e1000e,i2c_i801,i915,iwlwifi,snd_hda_intel,snd_sof_pci_intel_tgl,spi_intel_pci"
    ];
  };

  # Input devices
  input = {
    keyboard = {
      name = [
        "AT Translated Set 2 keyboard"
        "DELL0A9E:00 214A:0028 Keyboard"
      ];
      evdev = [
        "/dev/keyboard0"
        "/dev/keyboard1"
      ];
    };

    mouse = {
      name = [
        "DELL0A9E:00 214A:0028 Mouse"
        "PS/2 Generic Mouse"
      ];
      evdev = [
        "/dev/mouse0"
        "/dev/mouse1"
      ];
    };

    touchpad = {
      name = [ "CUST0000:00 0EEF:C003" ];
      evdev = [ "/dev/touchpad0" ];
    };

    misc = {
      name = [
        # "Lid Switch" "Video Bus" "HDA Intel PCH Headphone Mic" "HDA Intel PCH HDMI/DP,pcm=3" "HDA Intel PCH HDMI/DP,pcm=7" "HDA Intel PCH HDMI/DP,pcm=8" "HDA Intel PCH HDMI/DP,pcm=9" "Power Button" "Sleep Button" "Intel HID events" "Intel HID 5 button array" "Dell WMI hotkeys"
      ];
      evdev = [
        # /dev/input/by-path/platform-INTC1051:00-event /dev/input/by-path/platform-PNP0C14:02-event
      ];
    };
  };

  # Main disk device
  disks = {
    disk1.device = "/dev/nvme0n1";
  };

  # Network devices for passthrough to netvm
  network = {
    #TODO Add the Ethernet device
    pciDevices = [
      {
        # Network controller: Intel Corporation Wi-Fi 6E(802.11ax) AX210/AX1675* 2x2 [Typhoon Peak] (rev 1a)
        name = "wlp0s5f0";
        path = "0000:72:00.0";
        vendorId = "8086";
        productId = "2725";
        # Detected kernel driver: iwlwifi
        # Detected kernel modules: iwlwifi
      }
    ];
    kernelConfig = {
      # Kernel modules are indicative only, please investigate with lsmod/modinfo
      stage1.kernelModules = [ ];
      stage2.kernelModules = [ "iwlwifi" ];
      kernelParams = [ ];
    };
  };

  # GPU devices for passthrough to guivm
  gpu = {
    pciDevices = [
      {
        # VGA compatible controller: Intel Corporation TigerLake-LP GT2 [Iris Xe Graphics] (rev 01)
        name = "gpu0";
        path = "0000:00:02.0";
        vendorId = "8086";
        productId = "9a49";
        # Detected kernel driver: i915
        # Detected kernel modules: i915
      }
    ];
    kernelConfig = {
      # Kernel modules are indicative only, please investigate with lsmod/modinfo
      stage1.kernelModules = [ "i915" ];
      stage2.kernelModules = [ ];
      kernelParams = [ "earlykms" ];
    };
  };

  # Audio device for passthrough to audiovm
  audio = {
    #TODO: Fix splitting the Ethernet from the Audio iommu
    pciDevices = [
      {
        # ISA bridge: Intel Corporation Tiger Lake-LP LPC Controller (rev 20)
        name = "snd0-0";
        path = "0000:00:1f.0";
        vendorId = "8086";
        productId = "a082";
        # Detected kernel driver:
        # Detected kernel modules:
      }
      {
        # Serial bus controller: Intel Corporation Tiger Lake-LP SPI Controller (rev 20)
        name = "snd0-1";
        path = "0000:00:1f.5";
        vendorId = "8086";
        productId = "a0a4";
        # Detected kernel driver: intel-spi
        # Detected kernel modules: spi_intel_pci
      }
      {
        # Audio device: Intel Corporation Tiger Lake-LP Smart Sound Technology Audio Controller (rev 20)
        name = "snd0-2";
        path = "0000:00:1f.3";
        vendorId = "8086";
        productId = "a0c8";
        # Detected kernel driver: snd_hda_intel
        # Detected kernel modules: snd_hda_intel,snd_sof_pci_intel_tgl
      }
      {
        # Ethernet controller: Intel Corporation Ethernet Connection (13) I219-LM (rev 20)
        name = "snd0-3";
        path = "0000:00:1f.6";
        vendorId = "8086";
        productId = "15fb";
        # Detected kernel driver: e1000e
        # Detected kernel modules: e1000e
      }
      {
        # SMBus: Intel Corporation Tiger Lake-LP SMBus Controller (rev 20)
        name = "snd0-4";
        path = "0000:00:1f.4";
        vendorId = "8086";
        productId = "a0a3";
        # Detected kernel driver: i801_smbus
        # Detected kernel modules: i2c_i801
      }
    ];
    kernelConfig = {
      # Kernel modules are indicative only, please investigate with lsmod/modinfo
      stage1.kernelModules = [ ];
      stage2.kernelModules = [
        "e1000e"
        "i2c_i801"
        "snd_hda_intel"
        "snd_sof_pci_intel_tgl"
        "spi_intel_pci"
      ];
      kernelParams = [ ];
    };
  };

  # USB devices for passthrough
  usb = {
    internal = [
      {
        name = "cam0";
        hostbus = "3";
        hostport = "6";
      }
    ];
    external = [
      # Add external USB devices here
    ];
  };
}
