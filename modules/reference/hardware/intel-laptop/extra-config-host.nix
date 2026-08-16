# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  ...
}:
{
  ghaf = {
    global-config.storage.encryption.enable = true;

    services.power-manager.suspend = {
      mode = lib.mkDefault "auto";
      s2idleModels = [ "System76 Darter Pro" ];
    };

    # Generic Intel laptop targets exercise the complete Crosvm stack. Keep
    # machine-specific targets on their existing VMM selections.
    virtualization.vmConfig = {
      defaultSysVmVmm = "crosvm";
      defaultAppVmVmm = "crosvm";
      # Override the encrypted AdminVM's conservative QEMU fallback; vm-tpm
      # wires TPM passthrough for Crosvm.
      sysvms.adminvm.vmm = "crosvm";
    };
  };

  # Add system76 and system76-io kernel modules to host
  hardware.system76.kernel-modules.enable = true;
}
