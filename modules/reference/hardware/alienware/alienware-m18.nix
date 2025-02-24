# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  # System name
  name = "Alienware Not Specified";

  # List of system SKUs covered by this configuration
  skus = [
    "0C9D Alienware m18 R2"
  ];

  # Host configuration
  host = {
    kernelConfig.kernelParams = [
      "intel_iommu=on,sm_on"
      "iommu=pt"
      "acpi_backlight=vendor"
      "acpi_osi=linux"
      #l"module_blacklist=i2c_i801,i915,iwlwifi,nouveau,nvidiafb,snd_hda_intel,snd_soc_avs,snd_sof_pci_intel_tgl,spi_intel_pci,xe"
      "module_blacklist=i915,iwlwifi,nouveau,nvidia,nvidiafb,xe"
      #"softdep"
      # "pre:"
      # "vfio-pci"
    ];
  };

  # Input devices
  input = {
    keyboard = {
      name = [
        "AT Translated Set 2 keyboard"
        "DELL Technologies Keyboard"
      ];
      evdev = [
        "/dev/keyboard0"
        "/dev/keyboard1"
      ];
    };

    mouse = {
      name = [
        #"VEN_04F3:00 04F3:328A Mouse"
        "PS/2 Generic Mouse"
      ];
      evdev = [
        "/dev/mouse0"
        #"/dev/mouse1"
      ];
    };

    touchpad = {
      name = [
        "VEN_04F3:00 04F3:328A Touchpad"
      ];
      evdev = [
        "/dev/touchpad0"
      ];
    };

    misc = {
      name = [
        # "Dell WMI hotkeys" "HDA NVidia HDMI/DP,pcm=8" "HDA NVidia HDMI/DP,pcm=9" "Video Bus" "sof-hda-dsp Headphone Mic" "sof-hda-dsp HDMI/DP,pcm=3" "sof-hda-dsp HDMI/DP,pcm=4" "Lid Switch" "sof-hda-dsp HDMI/DP,pcm=5" "Power Button" "Sleep Button" "Intel HID events" "Intel HID 5 button array" "HDA NVidia HDMI/DP,pcm=3" "HDA NVidia HDMI/DP,pcm=7"
      ];
      evdev = [
        # /dev/input/by-path/platform-PNP0C14:03-event /dev/input/by-path/pci-0000:00:1f.3-platform-skl_hda_dsp_generic-event /dev/input/by-path/platform-INTC1070:00-event
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
        # Network controller: Intel Corporation Wi-Fi 7(802.11be) AX1775*/AX1790*/BE20*/BE401/BE1750* 2x2 (rev 1a)
        name = "wlp0s5f0";
        path = "0000:6d:00.0";
        vendorId = "8086";
        productId = "272b";
        # Detected kernel driver: iwlwifi
        # Detected kernel modules: iwlwifi
      }
      {
        # Ethernet controller: Realtek Semiconductor Co., Ltd. Device 5000 (rev 02)
        name = "eth0";
        path = "0000:6f:00.0";
        vendorId = "10ec";
        productId = "5000";
        # Detected kernel driver:
        # Detected kernel modules:
      }
    ];
    kernelConfig = {
      # Kernel modules are indicative only, please investigate with lsmod/modinfo
      stage1.kernelModules = [ ];
      stage2.kernelModules = [
        "iwlwifi"
      ];
      kernelParams = [ ];
    };
  };

  # GPU devices for passthrough to guivm
  gpu = {
    pciDevices = [
      {
        # VGA compatible controller [0300]: Intel Corporation Raptor Lake-S UHD Graphics [8086:a788] (rev 04)
        name = "gpu0-0";
        path = "0000:00:02.0";
        vendorId = "8086";
        productId = "a788";
        # Detected kernel driver: nouveau
        # Detected kernel modules: nvidiafb,nouveau
      }
      {
        # Communication controller [0780]: Intel Corporation Raptor Lake CSME HECI #1 [8086:7a68] (rev 11)
        path = "0000:00:16.0";
        vendorId = "8086";
        productId = "7a68";

      }
      {
        # VGA compatible controller: NVIDIA Corporation AD103M / GN21-X11 [GeForce RTX 4090 Laptop GPU] (rev a1)
        name = "gpu1-0";
        path = "0000:01:00.0";
        vendorId = "10de";
        productId = "2757";
        # Detected kernel driver: snd_hda_intel
        # Detected kernel modules: snd_hda_intel
      }
      {
        # Audio device [0403]: NVIDIA Corporation Device [10de:22bb] (rev a1)
        name = "gpu1-1";
        path = "0000:01:00.1";
        vendorId = "10de";
        productId = "22bb";
        # Detected kernel driver: snd_hda_intel
        # Detected kernel modules: snd_hda_intel
      }
    ];
    kernelConfig = {
      # Kernel modules are indicative only, please investigate with lsmod/modinfo
      stage1.kernelModules = [
        "i915"
        "xe"
        "nvidia"
        "snd_hda_intel"
      ];
      stage2.kernelModules = [ ];
      kernelParams = [
        "earlykms"
      ];
    };
  };

  # Audio device for passthrough to audiovm
  audio = {
    pciDevices = [
      {
        # ISA bridge: Intel Corporation Device 7a0c (rev 11)
        name = "snd0-0";
        path = "0000:00:1f.0";
        vendorId = "8086";
        productId = "7a0c";
        # Detected kernel driver:
        # Detected kernel modules:
      }
      {
        # Serial bus controller: Intel Corporation Raptor Lake SPI (flash) Controller (rev 11)
        name = "snd0-1";
        path = "0000:00:1f.5";
        vendorId = "8086";
        productId = "7a24";
        # Detected kernel driver: intel-spi
        # Detected kernel modules: spi_intel_pci
      }
      {
        # Multimedia audio controller: Intel Corporation Raptor Lake High Definition Audio Controller (rev 11)
        name = "snd0-2";
        path = "0000:00:1f.3";
        vendorId = "8086";
        productId = "7a50";
        # Detected kernel driver: sof-audio-pci-intel-tgl
        # Detected kernel modules: snd_hda_intel,snd_soc_avs,snd_sof_pci_intel_tgl
      }
      {
        # SMBus: Intel Corporation Raptor Lake-S PCH SMBus Controller (rev 11)
        name = "snd0-3";
        path = "0000:00:1f.4";
        vendorId = "8086";
        productId = "7a23";
        # Detected kernel driver: i801_smbus
        # Detected kernel modules: i2c_i801
      }
    ];
    kernelConfig = {
      # Kernel modules are indicative only, please investigate with lsmod/modinfo
      stage1.kernelModules = [ ];
      stage2.kernelModules = [
        "i2c_i801"
        "snd_hda_intel"
        "snd_soc_avs"
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
        hostbus = "1";
        hostport = "8";
      }
    ];
    external = [
      # Add external USB devices here
    ];
  };
}
