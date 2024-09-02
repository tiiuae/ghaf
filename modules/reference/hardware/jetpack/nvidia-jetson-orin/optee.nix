# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, ... }:
{
  options.ghaf.hardware.nvidia.orin.optee = {
    xtest = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc ''
        Adds OP-TEE's xtest and related TA/Plugins
      '';
    };

    pkcs11-tool = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc ''
        OpenSC pkcs11-tool, but for a convenience reasons \"pkcs11-tool-optee\" shell
        script is created. It calls pkcs11-tool with "--module"-option set to
        OP-TEE's PKCS#11 library.

        Example usage: same as pkcs11-tool, but ommit "--module"-option

        pkcs11-tool-optee --help
        pkcs11-tool-optee --show-info -L
      '';
    };

    pkcs11 = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = lib.mdDoc ''
          Adds OP-TEE's PKCS#11 TA.
        '';
      };

      heapSize = lib.mkOption {
        type = lib.types.int;
        default = 32768;
        description = lib.mdDoc ''
          Defines PKCS11 TA heap size. Heap size has a direct
          correlation to its secure storage size. Heap == Storage.

          NOTE: Redefining secure storage size once it has been created
          might corrupt existing storage. Default storage path /data/tee.
          Remove existing storage when redefined.
        '';
      };

      tokenCount = lib.mkOption {
        type = lib.types.int;
        default = 3;
        description = lib.mdDoc ''
          PKCS#11 token count.

          NOTE: Redefining token count might corrupt secure storage,
          if it exist. Default storage path /data/tee.
          Remove existing storage when redefined.
        '';
      };
    };
  };
}
