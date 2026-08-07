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
  _file = ./usb-authorization.nix;

  options.ghaf.hardware.usb.authorization = {
    enable = mkEnableOption "host USB authorization policy";

    deauthorizeUnmatched = mkOption {
      type = types.bool;
      default = false;
      description = ''
        At startup, deauthorize every connected USB device that is not a hub,
        not the USB boot device, not currently attached to a VM, and not
        listed in hostAllow. Devices are authorized again as their target VM
        claims them; passthrough rules are not consulted by this sweep.
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
        Optional boot-time usbcore.authorized_default kernel parameter. This
        applies from initrd, before vhotplug runs. Do not set it to 0 on a
        system that needs USB during early boot: booting from USB media,
        typing a disk-encryption passphrase on a USB keyboard, and the fido2
        disk-encryption backend all break. 2 authorizes only ACPI-described
        internal ports, and degrades to 0 on firmware without ACPI port data.
        Changing this option changes the kernel command line and requires
        reflashing the image; ghaf-rebuild switch is insufficient.
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
