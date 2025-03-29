# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  # System name
  name = "Gigabyte Technology Co., Ltd. -CF-IDO";

  # List of system SKUs covered by this configuration
  skus = [
    "Mk1"
  ];

  type = "desktop";

  # Host configuration
  host = {
    kernelConfig.kernelParams = [
      "intel_iommu=on,sm_on"
      "iommu=pt"
      "acpi_backlight=vendor"
      "acpi_osi=linux"
      "module_blacklist=iwlwifi,r8169,i2c_i801,i915,nouveau,nvidiafb,snd_hda_intel,snd_sof_pci_intel_mtl,spi_intel_pci,xe"
    ];
  };

  # Input devices
  input = {
    keyboard = {
      name = [ ];
      evdev = [ ];
    };

    mouse = {
      name = [ ];
      evdev = [ ];
    };

    touchpad = {
      name = [ ];
      evdev = [ ];
    };

    misc = {
      name = [
        # "HDA NVidia HDMI/DP,pcm=7" "HDA NVidia HDMI/DP,pcm=8" "HDA NVidia HDMI/DP,pcm=9" "Video Bus" "HDA Intel PCH Rear Mic" "HDA Intel PCH Front Mic" "HDA Intel PCH Line" "HDA Intel PCH Line Out" "HDA Intel PCH Front Headphone" "HDA Intel PCH HDMI/DP,pcm=3" "HDA Intel PCH HDMI/DP,pcm=7" "HDA Intel PCH HDMI/DP,pcm=8" "HDA Intel PCH HDMI/DP,pcm=9" "Sleep Button" "Power Button" "Intel HID events" "HDA NVidia HDMI/DP,pcm=3"
      ];
      evdev = [
        # /dev/input/by-path/pci-0000:80:14.0-usbv2-0:12.3:1.1-event /dev/input/by-path/pci-0000:80:14.0-usb-0:12.3:1.1-event /dev/input/by-id/usb-Microsoft_Microsoft®_Nano_Transceiver_v2.0-event-if01 /dev/input/by-path/pci-0000:80:14.0-usb-0:12.3:1.2-event-joystick /dev/input/by-path/pci-0000:80:14.0-usbv2-0:12.3:1.2-event-joystick /dev/input/by-id/usb-Microsoft_Microsoft®_Nano_Transceiver_v2.0-if02-event-joystick /dev/input/by-path/platform-INTC10CB:00-event
      ];
    };
  };

  # Main disk device
  disks = {
    disk1.device = "/dev/nvme0n1";
  };

  # Network devices for passthrough to netvm
  network = {
    pciDevices = [
      {
        # Network controller: Intel Corporation Device 7f70 (rev 10)
        name = "wlp0s5f0";
        path = "0000:80:14.3";
        vendorId = "8086";
        productId = "7f70";
        # Detected kernel driver: iwlwifi
        # Detected kernel modules: iwlwifi
      }
      {
        # Ethernet controller: Realtek Semiconductor Co., Ltd. RTL8125 2.5GbE Controller (rev 0c)
        name = "eth0";
        path = "0000:82:00.0";
        vendorId = "10ec";
        productId = "8125";
        # Detected kernel driver:
        # Detected kernel modules: r8169
      }
    ];
    kernelConfig = {
      # Kernel modules are indicative only, please investigate with lsmod/modinfo
      stage1.kernelModules = [ ];
      stage2.kernelModules = [
        "iwlwifi"
        "r8169"
      ];
      kernelParams = [ ];
    };
  };

  # GPU devices for passthrough to guivm
  gpu = {
    pciDevices = [

      {
        # VGA compatible controller: NVIDIA Corporation Device 2c02 (rev a1)
        name = "gpu1-0";
        path = "0000:02:00.0";
        vendorId = "10de";
        productId = "2c02";
        # Detected kernel driver:
        # Detected kernel modules: nvidiafb,nouveau
      }
      {
        # Audio device: NVIDIA Corporation Device 22e9 (rev a1)
        name = "gpu1-1";
        path = "0000:02:00.1";
        vendorId = "10de";
        productId = "22e9";
        # Detected kernel driver: snd_hda_intel
        # Detected kernel modules: snd_hda_intel
      }

      # {
      #   # VGA compatible controller [0300]: Intel Corporation Arrow Lake-S
      #   name = "gpu1";
      #   path = "0000:00:02.0";
      #   vendorId = "8086";
      #   productId = "7d67";
      #   # Detected kernel driver:
      #   # Detected kernel modules:
      # }
    ];
    kernelConfig = {
      # Kernel modules are indicative only, please investigate with lsmod/modinfo
      stage1.kernelModules = [
        "nouveau"
        "nvidiafb"
        "snd_hda_intel"
      ];
      stage2.kernelModules = [ ];
      kernelParams = [
        "earlykms"
        #"module_blacklist=nouveau"
      ];
    };
  };
  # Audio device for passthrough to audiovm
  audio = {
    pciDevices = [
      {
        # SMBus: Intel Corporation Device 7f23 (rev 10)
        name = "snd1-0";
        path = "0000:80:1f.4";
        vendorId = "8086";
        productId = "7f23";
        # Detected kernel driver: i801_smbus
        # Detected kernel modules: i2c_i801
      }
      {
        # ISA bridge: Intel Corporation Device 7f04 (rev 10)
        name = "snd1-1";
        path = "0000:80:1f.0";
        vendorId = "8086";
        productId = "7f04";
        # Detected kernel driver:
        # Detected kernel modules:
      }
      {
        # Serial bus controller: Intel Corporation Device 7f24 (rev 10)
        name = "snd1-2";
        path = "0000:80:1f.5";
        vendorId = "8086";
        productId = "7f24";
        # Detected kernel driver: intel-spi
        # Detected kernel modules: spi_intel_pci
      }
      {
        # Audio device: Intel Corporation Device 7f50 (rev 10)
        name = "snd1-3";
        path = "0000:80:1f.3";
        vendorId = "8086";
        productId = "7f50";
        # Detected kernel driver: snd_hda_intel
        # Detected kernel modules: snd_hda_intel,snd_sof_pci_intel_mtl
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
      kernelParams = [ ];
    };
  };

  # USB devices for passthrough
  usb = {
    internal = [ ];
    external = [
      {
        name = "usbKBD";
        vendorId = "045e";
        productId = "0800";
      }
    ]; # Add external USB devices here
  };
}
