# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  ...
}: let
  cfg = config.ghaf.hardware.nvidia.orin.agx-milboard;
in {
  options.ghaf.hardware.nvidia.orin.agx-milboard.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Enable Milboard-AGX configuration for NVIDIA Orin

      This option is an implementation level detail and is toggled automatically
      by targets that need it. There should be no manual configuration for this
      option.
    '';
  };

  config = lib.mkIf cfg.enable {
    boot.kernelPatches = [
      {
        name = "Added Configurations to Support Milboard AGX";
        patch = null;
        extraStructuredConfig = with lib.kernel; {
          PCIE_ECRC = lib.mkDefault no;
          PCIEASPM_POWER_SUPERSAVE = lib.mkDefault no;
          PCIEASPM_POWERSAVE = lib.mkDefault yes;
          PCI_EPF_TEST = lib.mkDefault no;
          USB_NET_CDC_MBIM = lib.mkDefault no;
          SERIAL_8250_XR17V35X = lib.mkDefault yes;
          RTC_HCTOSYS_DEVICE = lib.mkDefault unset;
          SENSORS_TMP102 = lib.mkDefault yes;
        };
      }
      {
        name = "Milboard AGX Patches";
        patch = ./agx-milboard.patch;
      }
    ];
  };
}
