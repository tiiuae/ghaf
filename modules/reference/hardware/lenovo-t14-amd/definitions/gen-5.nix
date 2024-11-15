# SPDX-FileCopyrightText: 2024 TII (SSRC) and the Ghaf contributors
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
      # Blacklist GPU drivers on host to prevent them from claiming devices before VFIO
      "module_blacklist=amdgpu,snd_hda_intel"
      # vfio-pci.ids auto-generated from pciDevices, no need to specify manually
    ];
  };

  # Input devices
  input = {
    misc = {
      name = [
        "ThinkPad Extra Buttons"
      ];
      evdev = [
        "/dev/input/by-path/platform-thinkpad_acpi-event"
      ];
    };
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
      stage1.kernelModules = [ ];
      stage2.kernelModules = [
        "ath12k"
        "r8169"
      ];
      kernelParams = [ ];
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
        # AMD iGPU, according to https://github.com/isc30/ryzen-gpu-passthrough-proxmox?tab=readme-ov-file
        # we have to also provide a vbios rom, but this didn't seem to work so far.
        # ../GPU_PASSTHROUGH_ISSUES.md for more details.
        #qemu.deviceExtraArgs = "romfile=${./vbios_1002_1900.bin}";
      }
      {
        # Audio device: Advanced Micro Devices, Inc. [AMD/ATI] Rembrandt Radeon High Definition Audio Controller
        # IMPORTANT: This must be passed through with the GPU (multi-function device)
        name = "gpu0-audio";
        path = "0000:c4:00.1";
        vendorId = "1002";
        productId = "1640";
        # Detected kernel driver: snd_hda_intel
        # Detected kernel modules: snd_hda_intel
        # with uefi firmware, apparently we also need the GOP driver rom
        # also didn't work so far.
        #qemu.deviceExtraArgs = "romfile=${./AMDGopDriver.rom}";
      }
    ];
    kernelConfig = {
      # Kernel modules are indicative only, please investigate with lsmod/modinfo
      stage1.kernelModules = [
        "amdgpu"
      ];
      stage2.kernelModules = [
        "snd_hda_intel" # For GPU audio function (c4:00.1)
      ];
      # Enable verbose logging for GPU debugging
      kernelParams = [
        "loglevel=7" # Show all kernel messages
        "ignore_loglevel" # Ignore quiet setting
      ];
    };
  };

  # Audio device for passthrough to audiovm
  audio = {
    # Disable ACPI NHLT table as it doesn't exist on this system
    acpiPath = null;
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
      # NOTE: GPU audio (0000:c4:00.1, 1002:1640) moved to GPU section
      # as it must be passed through with the GPU (multi-function device)
      {
        # Multimedia controller: Advanced Micro Devices, Inc. [AMD] ACP/ACP3X/ACP6x Audio Coprocessor
        name = "snd1";
        path = "0000:c4:00.5";
        vendorId = "1022";
        productId = "15e2";
        # Detected kernel driver: snd_rn_pci_acp3x
        # Detected kernel modules: snd_rn_pci_acp3x, snd_pci_acp3x
      }
    ];
    kernelConfig = {
      # Kernel modules are indicative only, please investigate with lsmod/modinfo
      stage1.kernelModules = [ ];
      stage2.kernelModules = [
        "snd_hda_intel"
        "snd_rn_pci_acp3x"
        "snd_pci_acp3x"
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
      hostport = "1";
    }
    # Bluetooth device - Foxconn / Hon Hai
    {
      name = "bt0";
      hostbus = "1";
      hostport = "3";
    }
    # Fingerprint reader - Goodix
    {
      name = "fpr0";
      hostbus = "1";
      hostport = "5";
    }
  ];
}
