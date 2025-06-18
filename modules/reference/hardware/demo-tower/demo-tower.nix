# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  # System name
  name = "Demo Tower";

  # List of system SKUs covered by this configuration
  skus = [ "Be Quiet mk1" ];

  type = "desktop";

  # Host configuration
  host = {
    kernelConfig.kernelParams = [
      "amd_iommu=force_isolation"
      "iommu=pt"
      "acpi_backlight=vendor"
      "acpi_osi=linux"
      "module_blacklist=i2c_nvidia_gpu,igb,iwlwifi,nouveau,nvidiafb,r8169,snd_hda_intel"
    ];
  };

  # Input devices
  input = {
    misc = {
      name = [
        # "HDA NVidia HDMI/DP,pcm=3" "HDA NVidia HDMI/DP,pcm=7" "HDA NVidia HDMI/DP,pcm=8" "HDA NVidia HDMI/DP,pcm=9" "Generic USB Audio Consumer Control" "Generic USB Audio" "Power Button"
      ];
      evdev = [
        # /dev/input/by-id/usb-Microsoft_Microsoft®_Nano_Transceiver_v2.0-event-if01 /dev/input/by-path/pci-0000:48:00.1-usb-0:1:1.1-event /dev/input/by-path/pci-0000:48:00.1-usbv2-0:1:1.1-event /dev/input/by-path/pci-0000:48:00.1-usb-0:1:1.2-event-joystick /dev/input/by-path/pci-0000:48:00.1-usbv2-0:1:1.2-event-joystick /dev/input/by-id/usb-Microsoft_Microsoft®_Nano_Transceiver_v2.0-if02-event-joystick /dev/input/by-path/pci-0000:48:00.3-usbv2-0:5:1.7-event /dev/input/by-path/pci-0000:48:00.3-usb-0:5:1.7-event /dev/input/by-id/usb-Generic_USB_Audio-event-if07 /dev/input/by-path/pci-0000:48:00.3-usb-0:5:1.7-event /dev/input/by-path/pci-0000:48:00.3-usbv2-0:5:1.7-event /dev/input/by-id/usb-Generic_USB_Audio-event-if07
      ];
    };
  };

  # Network devices for passthrough to netvm
  network = {
    pciDevices = [
      {
        # Network controller: Intel Corporation Wi-Fi 6 AX200 (rev 1a)
        name = "wlp0s5f1";
        path = "0000:46:00.0";
        vendorId = "8086";
        productId = "2723";
        # Detected kernel driver: iwlwifi
        # Detected kernel modules: iwlwifi
      }
      {
        # Ethernet controller: Realtek Semiconductor Co., Ltd. RTL8125 2.5GbE Controller (rev 01)
        name = "eth1";
        path = "0000:47:00.0";
        vendorId = "10ec";
        productId = "8125";
        # Detected kernel driver: r8169
        # Detected kernel modules: r8169
      }
      {
        # Ethernet controller [0200]: Intel Corporation I211 Gigabit Network Connection [8086:1539] (rev 03)
        name = "eth0";
        path = "0000:45:00.0";
        vendorId = "8086";
        productId = "1539";
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
        # USB controller: NVIDIA Corporation TU104 USB 3.1 Host Controller (rev a1)
        name = "gpu0-0";
        path = "0000:01:00.2";
        vendorId = "10de";
        productId = "1ad8";
        # Detected kernel driver: xhci_hcd
        # Detected kernel modules: xhci_pci
      }
      {
        # VGA compatible controller: NVIDIA Corporation TU104GL [Quadro RTX 4000] (rev a1)
        name = "gpu0-1";
        path = "0000:01:00.0";
        vendorId = "10de";
        productId = "1eb1";
        # Detected kernel driver: nouveau
        # Detected kernel modules: nvidiafb,nouveau
      }
      {
        # Serial bus controller: NVIDIA Corporation TU104 USB Type-C UCSI Controller (rev a1)
        name = "gpu0-2";
        path = "0000:01:00.3";
        vendorId = "10de";
        productId = "1ad9";
        # Detected kernel driver: nvidia-gpu
        # Detected kernel modules: i2c_nvidia_gpu
      }
      {
        # Audio device: NVIDIA Corporation TU104 HD Audio Controller (rev a1)
        name = "gpu0-3";
        path = "0000:01:00.1";
        vendorId = "10de";
        productId = "10f8";
        # Detected kernel driver: snd_hda_intel
        # Detected kernel modules: snd_hda_intel
      }
    ];
    kernelConfig = {
      # Kernel modules are indicative only, please investigate with lsmod/modinfo
      stage1.kernelModules = [
        "i2c_nvidia_gpu"
        "nvidiafb"
        "snd_hda_intel"
        "xhci_pci"
      ];
      stage2.kernelModules = [ ];
      kernelParams = [
        "earlykms"
        "module_blacklist=nouveau"
      ];
    };
  };

  # Audio device for passthrough to audiovm
  audio = {
    acpiPath = null;
    pciDevices = [
      {
        # Audio device: Advanced Micro Devices, Inc. [AMD] Starship/Matisse HD Audio Controller
        name = "snd1";
        path = "0000:22:00.4";
        vendorId = "1022";
        productId = "1487";
        # Detected kernel driver: snd_hda_intel
        # Detected kernel modules: snd_hda_intel
      }
    ];
    kernelConfig = {
      # Kernel modules are indicative only, please investigate with lsmod/modinfo
      stage1.kernelModules = [ ];
      stage2.kernelModules = [
        "snd_hda_intel"
      ];
      kernelParams = [ ];
    };
  };

  # USB devices for passthrough
  usb.deviceList = [
    {
      vms = [ "gui-vm" ];
      name = "usbKBD";
      vendorId = "045e";
      productId = "0800";
    }
  ];
}
