# Copyright 2025-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ lib, ... }:
let
  inherit (lib)
    mkOption
    types
    literalExpression
    ;
in
{
  options.ghaf.hardware.passthrough = {
    mode = mkOption {
      description = ''
        Pass through mode for the pre attached devices defined in hardware.passthrough.usb.deviceList.
        Options: "static", "dynamic", "user"
        "none": no passthrough
        "static": legacy mode, static passthrough via qemu
        "dynamic": dynamic passthrough via hotplug in runtime
        "user": user defined passthrough [Not supported]
      '';
      type = types.str;
      default = "static";
    };

    qemuExtraArgs = mkOption {
      type = types.attrsOf (types.listOf types.str);
      default = { };
      description = ''
        Extra arguments to pass to qemu when enabling the internal USB device(s).
        Qemu arguments for the devices are grouped by vm-name.
      '';
      example = literalExpression ''
        {
          "vm-name1" = [
            "-device qemu-xhci -device usb-host,vendorid=0x0001,productid=0x0001"
            ];
          "vm-name2" = [
            "-device qemu-xhci -device usb-host,vendorid=0x1234,productid=0x1234"
            ];
        }
      '';
    };

    vmUdevExtraRules = mkOption {
      type = types.attrsOf (types.listOf types.str);
      default = { };
      description = ''
        Extra udev rules to be used by the specified vm.
      '';
      example = literalExpression ''
        {
          "vm-name1" = [
            "udev rule 1"
            "udev rule 2"
          ];
        }
      '';
    };
  };

}
