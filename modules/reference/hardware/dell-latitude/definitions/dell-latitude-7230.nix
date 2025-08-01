# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  # System name
  name = "Dell Latitude 7230 Rugged";

  # List of system SKUs covered by this configuration
  skus = [ "0BB7 Latitude 7230 Rugged Extreme Tablet" ];

  # Host configuration
  host = {
    kernelConfig.kernelParams = [
      "intel_iommu=on,sm_on"
      "iommu=pt"
      "acpi_backlight=vendor"
      "acpi_osi=linux"
      "module_blacklist=i915,xe,iwlwifi,snd_hda_intel,snd_sof_pci_intel_tgl,bluetooth,btusb"
    ];
  };

  # Input devices
  input = {
    misc = {
      name = [
        # "Intel HID events" "Dell WMI hotkeys" "Video Bus" "HDA Intel PCH Headphone Mic" "HDA Intel PCH HDMI/DP,pcm=3" "HDA Intel PCH HDMI/DP,pcm=7" "HDA Intel PCH HDMI/DP,pcm=8" "HDA Intel PCH HDMI/DP,pcm=9" "Intel HID 5 button array" "Lid Switch" "Power Button" "Sleep Button"
      ];
      evdev = [
        # /dev/input/by-path/platform-INTC1070:00-event /dev/input/by-path/platform-PNP0C14:02-event
      ];
    };
  };

  # Network devices for passthrough to netvm
  network = {
    pciDevices = [
      {
        # Network controller: Intel Corporation Alder Lake-P PCH CNVi WiFi (rev 01)
        name = "wlp0s5f0";
        path = "0000:00:14.3";
        vendorId = "8086";
        productId = "51f0";
        # Detected kernel driver: iwlwifi
        # Detected kernel modules: iwlwifi
      }
    ];
    kernelConfig = {
      stage1.kernelModules = [ ];
      stage2.kernelModules = [ "iwlwifi" ];
      kernelParams = [ ];
    };
  };

  # GPU devices for passthrough to guivm
  gpu = {
    pciDevices = [
      {
        # VGA compatible controller: Intel Corporation Alder Lake-UP4 GT2 [Iris Xe Graphics] (rev 0c)
        name = "gpu0";
        path = "0000:00:02.0";
        vendorId = "8086";
        productId = "46aa";
        # opregion is required for type-c display to work
        qemu.deviceExtraArgs = "x-igd-opregion=on";
        # Detected kernel driver: i915
        # Detected kernel modules: i915
      }
    ];
    kernelConfig = {
      stage1.kernelModules = [ ];
      stage2.kernelModules = [ ];
      kernelParams = [ ];
    };
  };

  # Audio device for passthrough to audiovm
  audio = {
    removePciDevice = "0000:00:1f.3";
    rescanPciDevice = "0000:00:1f.0";
    acpiPath = "/sys/firmware/acpi/tables/NHLT";
    pciDevices = [
      {
        # ISA bridge: Intel Corporation Alder Lake LPC Controller (rev 01)
        name = "snd0-0";
        path = "0000:00:1f.0";
        vendorId = "8086";
        productId = "5187";
        # Detected kernel driver:
        # Detected kernel modules:
      }
      {
        # Serial bus controller: Intel Corporation Alder Lake-P PCH SPI Controller (rev 01)
        name = "snd0-1";
        path = "0000:00:1f.5";
        vendorId = "8086";
        productId = "51a4";
        # Detected kernel driver: intel-spi
        # Detected kernel modules: spi_intel_pci
      }
      {
        # Audio device: Intel Corporation Alder Lake Smart Sound Technology Audio Controller (rev 01)
        name = "snd0-2";
        path = "0000:00:1f.3";
        vendorId = "8086";
        productId = "51cc";
        # Detected kernel driver: snd_hda_intel
        # Detected kernel modules: snd_hda_intel,snd_sof_pci_intel_tgl
      }
      {
        # SMBus: Intel Corporation Alder Lake PCH-P SMBus Host Controller (rev 01)
        name = "snd0-3";
        path = "0000:00:1f.4";
        vendorId = "8086";
        productId = "51a3";
        # Detected kernel driver: i801_smbus
        # Detected kernel modules: i2c_i801
      }
    ];
    kernelConfig = {
      stage1.kernelModules = [ ];
      stage2.kernelModules = [
        "i2c_i801"
        "snd_hda_intel"
        "snd_sof_pci_intel_tgl"
        "spi_intel_pci"
      ];
      kernelParams = [ "snd_intel_dspcfg.dsp_driver=0" ];
    };
  };

  # USB devices for passthrough
  usb.devices = [
    # GPS
    {
      name = "gps0";
      hostbus = "3";
      hostport = "7";
    }
    # Bluetooth controller
    {
      name = "bt0";
      hostbus = "3";
      hostport = "10";
    }
  ];

}
