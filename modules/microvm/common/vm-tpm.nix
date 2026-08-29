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
  vmm = config.microvm.hypervisor;
  emulatedSocket =
    if cfg.emulated.runInVM then "vtpm.sock" else "/var/lib/swtpm/${cfg.emulated.name}/sock";
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
        config.ghaf.security.tpm2.tools
        pkgs.tpm2-tss
        config.ghaf.security.tpm2.pkcs11
        pkgs.tpm2-openssl
      ];

      boot.kernelPatches = lib.optionals (vmm == "crosvm") [
        {
          name = "chromiumos-virtio-tpm";
          patch = ../sysvms/patches/chromiumos-virtio-tpm.patch;
          structuredExtraConfig.TCG_VIRTIO_VTPM = lib.kernel.module;
        }
      ];

      # Encrypted VM storage is unlocked in initrd. Crosvm's TPM frontend uses
      # the virtio transport, so loading this only in stage 2 makes first-boot
      # enrollment succeed but leaves the next boot unable to unlock vmdata.
      boot.initrd.kernelModules = lib.optionals (vmm == "crosvm") [ "tpm_virtio" ];
    })
    (mkIf cfg.passthrough.enable {
      assertions = [
        {
          assertion = pkgs.stdenv.hostPlatform.isx86_64;
          message = "TPM passthrough is only supported on x86_64";
        }
      ];

      microvm.qemu = mkIf (vmm == "qemu") {
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
      microvm.crosvm.extraArgs = lib.mkIf (vmm == "crosvm") (
        lib.mkAfter [
          "--tpm-device"
          "/dev/tpmrm0"
        ]
      );
    })
    (mkIf (cfg.emulated.enable && config.microvm.hypervisor == "qemu") {
      microvm.qemu.extraArgs = [
        "-chardev"
        "socket,id=chrtpm,path=${emulatedSocket}"
        "-tpmdev"
        "emulator,id=tpm0,chardev=chrtpm"
        "-device"
        # tpm-tis is the x86 ISA/MMIO frontend; arm virt machines only have the
        # sysbus variant tpm-tis-device (plain tpm-tis fails "not a valid
        # device model name" and the VM exits at startup).
        "${if pkgs.stdenv.hostPlatform.isx86_64 then "tpm-tis" else "tpm-tis-device"},tpmdev=tpm0"
      ];
    })
    (mkIf (cfg.emulated.enable && config.microvm.hypervisor == "crosvm") {
      microvm.crosvm.extraArgs = lib.mkAfter [
        "--swtpm"
        emulatedSocket
      ];
    })
  ];
}
