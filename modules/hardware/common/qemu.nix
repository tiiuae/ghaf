# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ config, lib, ... }:
let
  inherit (builtins) hasAttr;
  inherit (lib)
    mkOption
    types
    optionals
    optionalAttrs
    ;
in
{
  options.ghaf.qemu = {
    guivm = mkOption {
      type = types.attrs;
      default = { };
      description = "Extra qemu arguments for GuiVM";
    };
    audiovm = mkOption {
      type = types.attrs;
      default = { };
      description = "Extra qemu arguments for AudioVM";
    };
  };

  config = {
    ghaf.qemu.guivm = optionalAttrs (hasAttr "hardware" config.ghaf) {
      microvm.qemu.extraArgs =
        optionals (config.ghaf.hardware.definition.type == "laptop") [
          # Button
          "-device"
          "button"
          # Battery
          "-device"
          "battery"
          # AC adapter
          "-device"
          "acad"
        ]
        ++ optionals (hasAttr "yubikey" config.ghaf.hardware.usb.external.qemuExtraArgs) config.ghaf.hardware.usb.external.qemuExtraArgs.yubikey
        ++ optionals (hasAttr "usbKBD" config.ghaf.hardware.usb.external.qemuExtraArgs) config.ghaf.hardware.usb.external.qemuExtraArgs.usbKBD
        ++ optionals (hasAttr "fpr0" config.ghaf.hardware.usb.internal.qemuExtraArgs) config.ghaf.hardware.usb.internal.qemuExtraArgs.fpr0
        ++ optionals config.ghaf.hardware.usb.vhotplug.enableEvdevPassthrough builtins.concatMap (n: [
          "-device"
          "pcie-root-port,bus=pcie.0,id=${config.ghaf.hardware.usb.vhotplug.pcieBusPrefix}${toString n},chassis=${toString n}"
        ]) (lib.range 1 config.ghaf.hardware.usb.vhotplug.pciePortCount);
    };
    ghaf.qemu.audiovm = optionalAttrs (hasAttr "hardware" config.ghaf) {
      microvm.qemu.extraArgs = optionals (hasAttr "bt0" config.ghaf.hardware.usb.internal.qemuExtraArgs) config.ghaf.hardware.usb.internal.qemuExtraArgs.bt0;
    };
  };
}
