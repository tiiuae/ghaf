# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  # System name
  name = "LENOVO ThinkPad T14 Gen 5";

  # List of system SKUs covered by this configuration
  skus = [
    "LENOVO_MT_21MC_BU_Think_FM_ThinkPad T14 Gen 5 21MCCTO1WW"
  ];

  # Host configuration
  host = {
    kernelConfig.kernelParams = [
      "amd_iommu=on"
      "iommu=pt"
      "acpi_backlight=vendor"
      "acpi_osi=linux"
      "module_blacklist=amdgpu"
      #"module_blacklist=amdgpu,ath12k,r8169,snd_acp_pci,snd_hda_intel,snd_pci_acp3x,snd_pci_acp5x,snd_pci_acp6x,snd_pci_ps,snd_rn_pci_acp3x,snd_rpl_pci_acp6x,snd_sof_amd_rembrandt,snd_sof_amd_renoir,snd_sof_amd_vangogh"
    ];
  };

  # Input devices
  input = {
    keyboard = {
      name = [
        "AT Translated Set 2 keyboard"
      ];
      evdev = [
        "/dev/keyboard0"
      ];
    };

    mouse = {
      name = [
        "TPPS/2 Elan TrackPoint"
        "ELAN0676:00 04F3:3195 Mouse"
      ];
      evdev = [
        "/dev/mouse0"
        "/dev/mouse1"
      ];
    };

    touchpad = {
      name = [
        "ELAN0676:00 04F3:3195 Touchpad"
      ];
      evdev = [
        "/dev/touchpad0"
      ];
    };

    misc = {
      name = [
        # "Power Button" "HD-Audio Generic Mic" "HD-Audio Generic Headphone" "ThinkPad Extra Buttons" "Lid Switch" "Sleep Button" "Video Bus" "HD-Audio Generic HDMI/DP,pcm=3" "HD-Audio Generic HDMI/DP,pcm=7" "HD-Audio Generic HDMI/DP,pcm=8"
      ];
      evdev = [
        # /dev/input/by-path/platform-thinkpad_acpi-event
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
        # Network controller: Qualcomm Technologies, Inc WCN785x Wi-Fi 7(802.11be) 320MHz 2x2 [FastConnect 7800] (rev 01)
        name = "wlp0s5f0";
        path = "0000:02:00.0";
        vendorId = "17cb";
        productId = "1107";
        # Detected kernel driver: ath12k_pci
        # Detected kernel modules: ath12k
      }
      {
        # Ethernet controller: Realtek Semiconductor Co., Ltd. RTL8111/8168/8211/8411 PCI Express Gigabit Ethernet Controller (rev 0e)
        name = "eth0";
        path = "0000:01:00.0";
        vendorId = "10ec";
        productId = "8168";
        # Detected kernel driver: r8169
        # Detected kernel modules: r8169
      }
    ];
    kernelConfig = {
      # Kernel modules are indicative only, please investigate with lsmod/modinfo
      stage1.kernelModules = [];
      stage2.kernelModules = [
        "ath12k"
        "r8169"
      ];
      kernelParams = [];
    };
  };

  # GPU devices for passthrough to guivm
  gpu = {
    pciDevices = [
      {
        # VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Phoenix3 (rev d0)
        name = "gpu0";
        path = "0000:c4:00.0";
        vendorId = "1002";
        productId = "1900";
        # Detected kernel driver: amdgpu
        # Detected kernel modules: amdgpu
      }
    ];
    kernelConfig = {
      # Kernel modules are indicative only, please investigate with lsmod/modinfo
      stage1.kernelModules = [
        "amdgpu"
      ];
      stage2.kernelModules = [];
      kernelParams = [
        "earlykms"
      ];
    };
  };

  # Audio device for passthrough to audiovm
  audio = {
    pciDevices = [
      {
        # Audio device: Advanced Micro Devices, Inc. [AMD] Family 17h/19h HD Audio Controller
        name = "snd2";
        path = "0000:c4:00.6";
        vendorId = "1022";
        productId = "15e3";
        # Detected kernel driver: snd_hda_intel
        # Detected kernel modules: snd_hda_intel
      }
    ];
    kernelConfig = {
      # Kernel modules are indicative only, please investigate with lsmod/modinfo
      stage1.kernelModules = [];
      stage2.kernelModules = [
        "snd_hda_intel"
      ];
      kernelParams = [];
    };
  };

  # USB devices for passthrough
  usb = {
    internal = [
      {
        name = "cam0";
        hostbus = "3";
        hostport = "1";
      }
    ];
    external = [
      # Add external USB devices here
    ];
  };
}
