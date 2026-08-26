# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  ...
}:
{
  # Keep the recovery menu available without delaying every normal boot by the
  # systemd-boot default timeout.
  boot.loader.timeout = lib.mkDefault 1;

  ghaf = {
    services.power-manager.suspend = {
      mode = lib.mkDefault "auto";
      s2idleModels = [ "System76 Darter Pro" ];
    };

    # Generic Intel laptop targets exercise the complete Crosvm stack. Keep
    # machine-specific targets on their existing VMM selections.
    #
    # mkDefault, so a downstream product can select a different VMM without
    # mkForce.
    virtualization.vmConfig = {
      defaultSysVmVmm = lib.mkDefault "crosvm";
      defaultAppVmVmm = lib.mkDefault "crosvm";
      # vm-tpm wires TPM passthrough for encrypted Crosvm variants.
      sysvms.adminvm.vmm = lib.mkDefault "crosvm";
    };
  };

  # Add system76 and system76-io kernel modules to host
  hardware.system76.kernel-modules.enable = true;
}
