# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  cfg = config.ghaf.hardware.usb.internal;
  inherit (lib)
    mkOption
    mkEnableOption
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
        else if ((dev.name != null) && (dev.hostbus != null) && (dev.hostport != null)) then
          {
            name = "${dev.name}";
            value = [
              "-device"
              "qemu-xhci"
              "-device"
              "usb-host,hostbus=${dev.hostbus},hostport=${dev.hostport}"
            ];
          }
        else
          builtins.throw ''
            The internal USB device is configured incorrectly.
                  Please provide name, and either vendorId and productId or hostbus and hostport.'';
    in
    builtins.listToAttrs (builtins.map generateArg config.ghaf.hardware.definition.usb.internal);

  # Create udev argument strings
  extraRules =
    let
      generateRule =
        dev:
        if ((dev.vendorId != null) && (dev.productId != null)) then
          ''SUBSYSTEM=="usb", ATTR{idVendor}=="${dev.vendorId}", ATTR{idProduct}=="${dev.productId}", GROUP="kvm"''
        else if ((dev.hostbus != null) && (dev.hostport != null)) then
          ''KERNEL=="${dev.hostbus}-${dev.hostport}", SUBSYSTEM=="usb", ATTR{busnum}=="${dev.hostbus}", GROUP="kvm"''
        else
          builtins.throw ''
            The internal USB device is configured incorrectly.
                  Please provide name, and either vendorId and productId or hostbus and hostport.'';
    in
    lib.strings.concatMapStringsSep "\n" generateRule config.ghaf.hardware.definition.usb.internal;
in
{
  options.ghaf.hardware.usb.internal = {
    enable = mkEnableOption "Enable internal USB device(s) passthrough support";
    qemuExtraArgs = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = ''
        Extra arguments to pass to qemu when enabling the internal USB device(s).
        Since there could be several devices that may need to be passed to different
        machines, the device names are used as keys to access the qemu arguments.
        Note that some devices require special names to be used correctly.
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
    # Qemu arguments for internal USB devices
    ghaf.hardware.usb.internal = {
      inherit qemuExtraArgs;
    };
    # Host udev rules for internal USB devices
    services.udev = {
      inherit extraRules;
    };
  };
}
