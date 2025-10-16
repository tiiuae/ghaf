# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
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

      runInVM = mkOption {
        description = ''
          Whether to run the swtpm instance on a separate VM or on the host.
          If set to false, the daemon runs on the host and keys are stored on 
          the host filesystem.
          If true, the swtpm daemon runs in the admin VM. This setup makes it 
          harder for a host process to access the guest keys.
        '';
        type = types.bool;
        default = false;
      };

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
          assertion = pkgs.stdenv.isx86_64;
          message = "TPM passthrough is only supported on x86_64";
        }
      ];

      microvm.qemu = {
        extraArgs = [
          "-tpmdev"
          "passthrough,id=tpmrm0,path=/dev/tpmrm0,cancel-path=/tmp/cancel"
          "-device"
          "tpm-tis,tpmdev=tpmrm0"
        ];

        # Workaround a bug when machine type is `microvm`
        #   tpm_tis MSFT0101:00: [Firmware Bug]: failed to get TPM2 ACPI table
        machine = "q35";
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
