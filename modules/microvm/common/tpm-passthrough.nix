# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.virtualization.microvm.tpm-passthrough;
  inherit (lib)
    types
    mkEnableOption
    mkOption
    mkIf
    ;
in
{
  options.ghaf.virtualization.microvm.tpm-passthrough = {
    enable = mkEnableOption "Passthrough of TPM-RM device";

    rootNVIndex = mkOption {
      type = types.str;
      description = "The NV index to use by this VM on the shared TPM";
    };
  };

  config = mkIf cfg.enable {

    security.tpm2.enable = true;

    microvm.qemu = {
      extraArgs = [
        "-tpmdev"
        "passthrough,id=tpmrm0,path=/dev/tpmrm0,cancel-path=/tmp/cancel"
        "-device"
        "tpm-tis,tpmdev=tpmrm0"
      ];
    };

    environment.systemPackages = [
      pkgs.tpm2-tools
      pkgs.tpm2-tss
      pkgs.tpm2-pkcs11
      pkgs.tpm2-openssl
    ];
  };
}
