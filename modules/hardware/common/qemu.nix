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
    ghaf.qemu.guivm = optionalAttrs (config.ghaf.type == "host") {
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
        ++ optionals (hasAttr "gui-vm" config.ghaf.hardware.passthrough.qemuExtraArgs) config.ghaf.hardware.passthrough.qemuExtraArgs.gui-vm;
    };
    ghaf.qemu.audiovm = optionalAttrs (config.ghaf.type == "host") {
      microvm.qemu.extraArgs =
        optionals (hasAttr "audio-vm" config.ghaf.hardware.passthrough.qemuExtraArgs) config.ghaf.hardware.passthrough.qemuExtraArgs.audio-vm
        ++ optionals (config.ghaf.hardware.definition.audio.acpiPath != null) [
          "-acpitable"
          "file=${config.ghaf.hardware.definition.audio.acpiPath}"
        ];
    };
  };
}
