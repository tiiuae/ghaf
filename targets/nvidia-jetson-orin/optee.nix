# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
#
# SPDX-License-Identifier: Apache-2.0
_:
(
  {
    pkgs,
    config,
    lib,
    ...
  }:
  let
    pkcs11-tool-optee = pkgs.writeShellScriptBin "pkcs11-tool-optee" ''
      exec "${pkgs.opensc}/bin/pkcs11-tool" --module "${pkgs.nvidia-jetpack.opteeClient}/lib/libckteec.so" $@
    '';
  in
  {
    hardware.nvidia-jetpack.firmware.optee = {
      pkcs11Support = config.ghaf.hardware.nvidia.orin.optee.pkcs11.enable;
      extraMakeFlags =
        (lib.optionals config.ghaf.hardware.nvidia.orin.optee.pkcs11.enable [
          "CFG_PKCS11_TA_TOKEN_COUNT=${toString config.ghaf.hardware.nvidia.orin.optee.pkcs11.tokenCount}"
          "CFG_PKCS11_TA_HEAP_SIZE=${toString config.ghaf.hardware.nvidia.orin.optee.pkcs11.heapSize}"
          "CFG_PKCS11_TA_AUTH_TEE_IDENTITY=${
            if config.ghaf.hardware.nvidia.orin.optee.pkcs11.authTeeIdentity then "y" else "n"
          }"
        ])
        ++ lib.optionals config.ghaf.hardware.nvidia.orin.optee.pkcs11.lockPinAfterFailedLoginAttempts [
          "CFG_PKCS11_TA_LOCK_PIN_AFTER_FAILED_LOGIN_ATTEMPTS=${
            if config.ghaf.hardware.nvidia.orin.optee.pkcs11.lockPinAfterFailedLoginAttempts then "y" else "n"
          }"
        ];
      patches = lib.optional config.ghaf.hardware.nvidia.orin.optee.pkcs11.lockPinAfterFailedLoginAttempts ./0001-ta-pkcs11-Build-time-option-for-controlling-pin-lock.patch;

      inherit (config.ghaf.hardware.nvidia.orin.optee) xtest;
    };

    environment.systemPackages = lib.optional config.ghaf.hardware.nvidia.orin.optee.pkcs11-tool pkcs11-tool-optee;
  }
)
