# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Module to customize the crosvm package used by microvm and its compilation
# options.
#
{
  lib,
  pkgs,
  ...
}:
{
  _file = ./crosvm.nix;

  options.ghaf.virtualization.crosvm = {
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.crosvm;
      defaultText = lib.literalExpression "pkgs.crosvm";
      description = "The crosvm package used across Ghaf modules.";
    };

    features = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional features to compile in crosvm binary";
    };

    patches = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "Patches to apply to crosvm.";
    };

    logLevel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "info";
      description = ''
        Value for crosvm `--log-level` option, applied to every microVM
        launched with the crosvm hypervisor. Set to null to leave at built-in
        default.
      '';
    };

    gdb = {
      enable = lib.mkEnableOption ''
        GDB debugging over local TCP.

        Careful! enabling this feature causes the VM to pause its boot sequence and wait for a
        GDB remote connection. It will not boot automatically on its own.
      '';
      port = lib.mkOption {
        type = lib.types.int;
        default = 9091;
        description = "Listen port of the guest GDB server";
      };
    };
  };
}
