# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  # System name
  name = "Micro-Star International Co., Ltd. 2.0";

  # List of system SKUs covered by this configuration
  skus = [
    "Default string MS-7E06"
  ];

  type = "desktop";

  # Host configuration
  host = {
    kernelConfig.kernelParams = [
      "intel_iommu=on,sm_on"
      "iommu=pt"
      "acpi_backlight=vendor"
      "acpi_osi=linux"
      "module_blacklist=nouveau,snd,snd_hda_intel,igc,iwlwifi,bluetooth"
    ];
  };

  # Input devices
  input = {
    misc = {
      name = [
        # "LiteOn Lenovo Calliope USB Keyboard" "HDA NVidia HDMI/DP,pcm=7" "HDA NVidia HDMI/DP,pcm=8" "HDA NVidia HDMI/DP,pcm=9" "HDA Intel PCH Rear Mic" "HDA Intel PCH Front Mic" "HDA Intel PCH Line" "HDA Intel PCH Line Out Front" "HDA Intel PCH Line Out Surround" "HDA Intel PCH Line Out CLFE" "HDA Intel PCH Line Out Side" "LiteOn Lenovo Calliope USB Keyboard System Control" "HDA Intel PCH Front Headphone" "HDA Intel PCH HDMI/DP,pcm=3" "HDA Intel PCH HDMI/DP,pcm=7" "HDA Intel PCH HDMI/DP,pcm=8" "HDA Intel PCH HDMI/DP,pcm=9" "LiteOn Lenovo Calliope USB Keyboard Consumer Control" "Sleep Button" "Power Button" "Video Bus" "HDA NVidia HDMI/DP,pcm=3"
      ];
      evdev = [
        # /dev/input/by-id/usb-LiteOn_Lenovo_Calliope_USB_Keyboard-event-kbd /dev/input/by-path/pci-0000:00:14.0-usb-0:11:1.0-event-kbd /dev/input/by-path/pci-0000:00:14.0-usbv2-0:11:1.0-event-kbd /dev/input/by-path/pci-0000:00:14.0-usb-0:11:1.1-event /dev/input/by-id/usb-LiteOn_Lenovo_Calliope_USB_Keyboard-event-if01 /dev/input/by-path/pci-0000:00:14.0-usbv2-0:11:1.1-event /dev/input/by-path/pci-0000:00:14.0-usbv2-0:11:1.1-event /dev/input/by-id/usb-LiteOn_Lenovo_Calliope_USB_Keyboard-event-if01 /dev/input/by-path/pci-0000:00:14.0-usb-0:11:1.1-event
      ];
    };
  };

  # Network devices for passthrough to netvm
  network = {
    pciDevices = [
      {
        # Network controller: Intel Corporation Raptor Lake-S PCH CNVi WiFi (rev 11)
        name = "wlp0s5f0";
        path = "0000:00:14.3";
        vendorId = "8086";
        productId = "7a70";
        # Detected kernel driver: iwlwifi
        # Detected kernel modules: iwlwifi
      }
      {
        # Ethernet controller: Intel Corporation Ethernet Controller I226-V (rev 04)
        name = "eth0";
        path = "0000:04:00.0";
        vendorId = "8086";
        productId = "125c";
        # Detected kernel driver: igc
        # Detected kernel modules: igc
      }
    ];
    kernelConfig = {
      # Kernel modules are indicative only, please investigate with lsmod/modinfo
      stage1.kernelModules = [ ];
      stage2.kernelModules = [
        "iwlwifi"
        "igc"
      ];
      kernelParams = [ ];
    };
  };

  # GPU devices for passthrough to guivm
  gpu = {
    pciDevices = [
      {
        # VGA compatible controller: NVIDIA Corporation GB203 [GeForce RTX 5080] (rev a1)
        name = "gpu0-0";
        path = "0000:01:00.0";
        vendorId = "10de";
        productId = "2c02";
        # Detected kernel driver:
        # Detected kernel modules: nvidiafb,nouveau
      }
      {
        # Audio device: NVIDIA Corporation Device 22e9 (rev a1)
        name = "gpu0-1";
        path = "0000:01:00.1";
        vendorId = "10de";
        productId = "22e9";
        # Detected kernel driver: snd_hda_intel
        # Detected kernel modules: snd_hda_intel
      }
    ];
    kernelConfig = {
      stage1.kernelModules = [
        "nvidia"
        "nvidia_drm"
        "nvidia_uvm"
        "nvidia_modeset"
      ];
      kernelParams = [
        "module_blacklist=nouveau"
      ];
    };
  };

  # Audio device for passthrough to audiovm
  audio = {
    pciDevices = [
      {
        # ISA bridge: Intel Corporation Raptor Lake LPC/eSPI Controller (rev 11)
        name = "snd0-0";
        path = "0000:00:1f.0";
        vendorId = "8086";
        productId = "7a04";
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
        # Audio device: Intel Corporation Raptor Lake High Definition Audio Controller (rev 11)
        name = "snd0-2";
        path = "0000:00:1f.3";
        vendorId = "8086";
        productId = "7a50";
        # Detected kernel driver: snd_hda_intel
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
        name = "bt0";
        vendorId = "8087";
        productId = "0033";
      }
    ];
    external = [
      # Add external USB devices here
    ];
  };
}
