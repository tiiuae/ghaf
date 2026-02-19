# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.virtualization.microvm.tpm;
  inherit (lib)
    types
    mkEnableOption
    mkOption
    mkIf
    mkMerge
    ;
in
{
  _file = ./vm-tpm.nix;
  options.ghaf.virtualization.microvm.tpm = {
    passthrough = {
      enable = mkEnableOption "Passthrough of TPM-RM device";

      rootNVIndex = mkOption {
        type = types.str;
        description = "The NV index to use by this VM on the shared TPM";
      };
    };

    emulated = {
      enable = mkEnableOption "Emulated TPM with swtpm";

      runInVM = mkEnableOption "running swtpm in a separate VM instead of on the host";

      name = mkOption {
        description = "Name of the VM";
        type = types.str;
        internal = true;
      };
    };
  };

  config = mkMerge [
    (mkIf (cfg.passthrough.enable || cfg.emulated.enable) {
      assertions = [
        {
          assertion = !(cfg.passthrough.enable && cfg.emulated.enable);
          message = "Cannot enable TPM passthrough and TPM emulation at the same time";
        }
      ];

      security.tpm2.enable = true;

      environment.systemPackages = [
        pkgs.tpm2-tools
        pkgs.tpm2-tss
        pkgs.tpm2-pkcs11
        pkgs.tpm2-openssl
      ];
    })
    (mkIf cfg.passthrough.enable {
      assertions = [
        {
          assertion = pkgs.stdenv.isx86_64 || pkgs.stdenv.isAarch64;
          message = "TPM passthrough is only supported on x86_64 and aarch64";
        }
      ];

      microvm.qemu = {
        extraArgs =
          let
            # x86_64 uses tpm-tis (ISA/LPC bus), aarch64 uses tpm-tis-device (MMIO/platform bus)
            tpmDevice = if pkgs.stdenv.isx86_64 then "tpm-tis" else "tpm-tis-device";
          in
          [
            "-tpmdev"
            "passthrough,id=tpmrm0,path=/dev/tpmrm0,cancel-path=/tmp/cancel"
            "-device"
            "${tpmDevice},tpmdev=tpmrm0"
          ];

        # Workaround a bug when machine type is `microvm`
        #   tpm_tis MSFT0101:00: [Firmware Bug]: failed to get TPM2 ACPI table
        # Only relevant for x86_64 (aarch64 uses "virt" machine type set by VM bases)
        machine = mkIf pkgs.stdenv.isx86_64 "q35";
      };
    })
    (mkIf cfg.emulated.enable {
      microvm.qemu.extraArgs = [
        "-chardev"
        "socket,id=chrtpm,path=${
          if cfg.emulated.runInVM then "vtpm.sock" else "/var/lib/swtpm/${cfg.emulated.name}/sock"
        }"
        "-tpmdev"
        "emulator,id=tpm0,chardev=chrtpm"
        "-device"
        "tpm-tis,tpmdev=tpm0"
      ];
    })
  ];
}
