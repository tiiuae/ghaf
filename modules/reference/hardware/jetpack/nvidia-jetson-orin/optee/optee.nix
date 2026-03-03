# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.orin.optee;
  inherit (lib)
    mkOption
    mkIf
    types
    ;

  pkcs11-tool-optee = pkgs.writeShellScriptBin "pkcs11-tool-optee" ''
    exec "${pkgs.opensc}/bin/pkcs11-tool" --module "${pkgs.nvidia-jetpack.opteeClient}/lib/libckteec.so" $@
  '';
in

{
  options.ghaf.hardware.nvidia.orin.optee = {

    enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Enables OP-TEE's related utilities

        NOTE: Option does not disable OP-TEE. It only
        removes some of the user space components.
      '';
    };

    xtest = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Adds OP-TEE's xtest and related TA/Plugins
      '';
    };

    pkcs11-tool = mkOption {
      type = types.bool;
      default = false;
      description = ''
        OpenSC pkcs11-tool, but for a convenience reasons \"pkcs11-tool-optee\" shell
        script is created. It calls pkcs11-tool with "--module"-option set to
        OP-TEE's PKCS#11 library.

        Example usage: same as pkcs11-tool, but ommit "--module"-option

        pkcs11-tool-optee --help
        pkcs11-tool-optee --show-info -L
      '';
    };

    pkcs11 = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Adds OP-TEE's PKCS#11 TA.
        '';
      };

      authTeeIdentity = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Enable PKCS#11 TA's TEE Identity based authentication support
        '';
      };

      lockPinAfterFailedLoginAttempts = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Locks correspondingly User or SO PIN when reaching maximum
          failed authentication attemps (continous) limit
        '';
      };

      heapSize = mkOption {
        type = types.int;
        default = 32768;
        description = ''
          Defines PKCS11 TA heap size. Heap size has a direct
          correlation to its secure storage size. Heap == Storage.

          NOTE: Redefining secure storage size once it has been created
          might corrupt existing storage. Default storage path /data/tee.
          Remove existing storage when redefined.
        '';
      };

      tokenCount = mkOption {
        type = types.int;
        default = 3;
        description = ''
          PKCS#11 token count.

          NOTE: Redefining token count might corrupt secure storage,
          if it exist. Default storage path /data/tee.
          Remove existing storage when redefined.
        '';
      };
    };
  };

  config = mkIf cfg.enable {

    hardware.nvidia-jetpack.firmware.optee = {
      pkcs11Support = cfg.pkcs11.enable;
      extraMakeFlags =
        (lib.optionals cfg.pkcs11.enable [
          "CFG_PKCS11_TA_TOKEN_COUNT=${toString cfg.pkcs11.tokenCount}"
          "CFG_PKCS11_TA_HEAP_SIZE=${toString cfg.pkcs11.heapSize}"
          "CFG_PKCS11_TA_AUTH_TEE_IDENTITY=${if cfg.pkcs11.authTeeIdentity then "y" else "n"}"
        ])
        ++ lib.optionals cfg.pkcs11.lockPinAfterFailedLoginAttempts [
          "CFG_PKCS11_TA_LOCK_PIN_AFTER_FAILED_LOGIN_ATTEMPTS=${
            if cfg.pkcs11.lockPinAfterFailedLoginAttempts then "y" else "n"
          }"
        ];
      patches = lib.optional cfg.pkcs11.lockPinAfterFailedLoginAttempts ./0001-ta-pkcs11-Build-time-option-for-controlling-pin-lock.patch;

      inherit (cfg) xtest;
    };

    environment.systemPackages = lib.optional cfg.pkcs11-tool pkcs11-tool-optee;
  };

}
