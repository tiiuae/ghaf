# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.ghaf.hardware.usb.authorization;
in
{
  _file = ./authorization.nix;

  options.ghaf.hardware.usb.authorization = {
    enable = mkEnableOption "host USB authorization policy";

    deauthorizeUnmatched = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Deauthorize already connected USB devices on system boot that
        do not match USB passthrough rules.
      '';
    };

    hostAllow = mkOption {
      type = types.listOf types.attrs;
      default = [ ];
      description = ''
        List of USB devices that vhotplug may authorize for use by the host.
        Rules use the same matching attributes as USB passthrough rules.
      '';
    };

    kernelDefault = mkOption {
      type = types.nullOr (
        types.enum [
          0
          1
          2
        ]
      );
      default = null;
      description = ''
        Optional boot-time usbcore.authorized_default kernel parameter. Leave
        this unset when the system may boot from USB media. Set it to 0 only
        for configurations that do not require USB storage during early boot.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.ghaf.hardware.passthrough.vhotplug.enable;
        message = "ghaf.hardware.usb.authorization requires ghaf.hardware.passthrough.vhotplug.enable.";
      }
    ];

    ghaf.hardware.passthrough.vhotplug.usbAuthorization = {
      enable = true;
      inherit (cfg) deauthorizeUnmatched hostAllow;
    };

    boot.kernelParams = mkIf (cfg.kernelDefault != null) [
      "usbcore.authorized_default=${toString cfg.kernelDefault}"
    ];
  };
}
