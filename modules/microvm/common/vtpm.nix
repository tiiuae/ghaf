# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.virtualization.microvm.vtpm;
  inherit (lib)
    types
    mkEnableOption
    mkOption
    mkIf
    ;
in
{
  options.ghaf.virtualization.microvm.vtpm = {
    enable = mkEnableOption "vTPM support in the virtual machine";
    basePort = mkOption {
      description = ''
        Listen port of the remote swtpm (vsock).
        Control channel is on <basePort> and data channel on
        <basePort+1>.
      '';
      type = types.int;
    };
  };

  config = mkIf cfg.enable {

    security.tpm2 = {
      enable = true;
      abrmd.enable = false;
    };

    microvm.qemu = {
      extraArgs = [
        "-chardev"
        "socket,id=chrtpm,path=vtpm.sock"
        "-tpmdev"
        "emulator,id=tpm0,chardev=chrtpm"
        "-device"
        "tpm-tis,tpmdev=tpm0"
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
