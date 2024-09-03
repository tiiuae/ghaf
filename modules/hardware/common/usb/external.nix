# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.hardware.usb.external;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    literalExpression
    ;

  # Create USB argument strings for Qemu
  qemuExtraArgs =
    let
      generateArg =
        dev:
        if ((dev.name != null) && (dev.vendorId != null) && (dev.productId != null)) then
          {
            name = "${dev.name}";
            value = [
              "-device"
              "qemu-xhci"
              "-device"
              "usb-host,vendorid=0x${dev.vendorId},productid=0x${dev.productId}"
            ];
          }
        else
          builtins.throw "The external USB device is configured incorrectly. Please provide name, vendorId and productId.";
    in
    builtins.listToAttrs (builtins.map generateArg config.ghaf.hardware.definition.usb.external);

  # Create udev argument strings
  extraRules =
    let
      generateRule =
        dev:
        if ((dev.vendorId != null) && (dev.productId != null)) then
          ''SUBSYSTEM=="usb", ATTR{idVendor}=="${dev.vendorId}", ATTR{idProduct}=="${dev.productId}", GROUP="kvm"''
        else
          builtins.throw "The external USB device is configured incorrectly. Please provide name, vendorId and productId.";
    in
    lib.strings.concatMapStringsSep "\n" generateRule config.ghaf.hardware.definition.usb.external;
in
{
  options.ghaf.hardware.usb.external = {
    enable = mkEnableOption "Enable external USB device(s) passthrough support";
    qemuExtraArgs = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = ''
        Extra arguments to pass to qemu when enabling the external USB device(s).
        Since there can be several devices that may need to be passed to different
        machines, the device names are used as keys to access the qemu arguments.
      '';
      example = literalExpression ''
        {
          "device1" = ["-device" "qemu-xhci" "-device" "usb-host,vendorid=0x1234,productid=0x1234"];
          "device2" = ["-device" "qemu-xhci" "-device" "usb-host,vendorid=0x0001,productid=0x0001"];
        }
      '';
    };
  };

  config = mkIf cfg.enable {
    ghaf.hardware.usb.external = {
      inherit qemuExtraArgs;
    };

    # Host udev rules for external USB devices
    services.udev = {
      inherit extraRules;
    };
  };
}
