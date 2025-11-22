# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  # System name
  name = "Intel Laptop";

  # List of system SKUs covered by this configuration
  skus = [ ];

  # Host configuration
  host = {
    kernelConfig.kernelParams = [
      "intel_iommu=on,sm_on"
      "iommu=pt"
      "acpi_backlight=vendor"
      "acpi_osi=linux"
      "module_blacklist=i915,xe,iwlwifi,snd_hda_intel,snd_sof_pci_intel_tgl,bluetooth,btusb,snd_pcm,mei_me,xesnd_hda_intel,snd_sof_pci_intel_lnl,spi_intel_pci,i801_smbus"
    ];
  };

  # Network devices for passthrough to netvm detected dynamically in vhotplug
  network.pciDevices = [
    {
      name = "wlp0s5f0";
      path = "";
    }
  ];

  # GPU devices generally don't handle hotplugging well
  # However, Intel integrated GPU usually has PCI address 0000:00:02.0, so we can keep it statically defined here
  gpu = {
    pciDevices = [
      {
        path = "0000:00:02.0";
        # Workaround: assign vfio-pci driver for all GPUs (PCI class 3)
        # vfio-pci.ids format is vendor:device[:subvendor[:subdevice[:class[:class_mask]]]]
        # This is required because different revisions of Intel graphics have different device IDs
        vendorId = "0:0";
        productId = "0:0:3:0";
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

  # Audio device for passthrough to audiovm detected dynamically in vhotplug
  audio = {
    kernelConfig = {
      stage1.kernelModules = [ ];
      stage2.kernelModules = [
        "i2c_i801"
        "snd_hda_intel"
        "snd_sof_pci_intel_tgl"
        "spi_intel_pci"
        "snd_soc_avs"
      ];
      kernelParams = [ ];
    };
  };
}
