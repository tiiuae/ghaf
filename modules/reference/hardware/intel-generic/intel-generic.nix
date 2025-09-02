# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  # System name
  name = "Intel Generic";

  # List of system SKUs covered by this configuration
  skus = [ ];

  # Host configuration
  host = {
    kernelConfig.kernelParams = [
      "intel_iommu=on,sm_on"
      "iommu=pt"
      "acpi_backlight=vendor"
      "acpi_osi=linux"
      "module_blacklist=i915.xe,iwlwifi,snd_hda_intel,snd_sof_pci_intel_tgl,bluetooth,btusb,snd_pcm,mei_me,xesnd_hda_intel,snd_sof_pci_intel_lnl,spi_intel_pci,i801_smbus"
    ];
  };

  # Network devices for passthrough to netvm
  network = {
    kernelConfig = {
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
    kernelConfig = {
      stage1.kernelModules = [
        "i915"
        "xe"
      ];
      stage2.kernelModules = [ ];
      kernelParams = [
        "earlykms"
        "i915.enable_dpcd_backlight=3"
      ];
    };
  };

  # Audio device for passthrough to audiovm
  audio = {
    removePciDevice = "0000:00:1f.3";
    rescanPciDevice = "0000:00:1f.0";
    acpiPath = "/sys/firmware/acpi/tables/NHLT";
    kernelConfig = {
      stage1.kernelModules = [ ];
      stage2.kernelModules = [
        "i2c_i801"
        "snd_hda_intel"
        "snd_sof_pci_intel_tgl"
        "spi_intel_pci"
        "snd_soc_avs"
      ];
      kernelParams = [ "snd_intel_dspcfg.dsp_driver=0" ];
    };
  };
}
