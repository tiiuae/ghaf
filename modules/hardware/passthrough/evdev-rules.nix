# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{ config, lib, ... }:
let
  inherit (lib)
    mkOption
    types
    mkIf
    optionals
    ;

  cfg = config.ghaf.hardware.passthrough.evdev;
  defaultEvdevRules = [
    {
      description = "Non-USB Input Devices for GUIVM";
      targetVm = "gui-vm";
      allow = [
        {
          property = "ID_INPUT_MOUSE";
          value = "1";
        }
        {
          property = "ID_INPUT_KEYBOARD";
          value = "1";
        }
        {
          property = "ID_INPUT_TOUCHPAD";
          value = "1";
        }
        {
          property = "ID_INPUT_TOUCHSCREEN";
          value = "1";
        }
        {
          property = "ID_INPUT_TABLET";
          value = "1";
        }
        {
          description = "ThinkPad Extra Buttons";
          pathTag = "platform-thinkpad_acpi";
        }
        {
          description = "Intel HID events";
          pathTag = "platform-INTC1070_00";
        }
        {
          description = "Intel HID events";
          pathTag = "platform-INT33D5:00";
        }
        {
          description = "Dell WMI hotkeys";
          pathTag = "platform-PNP0C14:02";
        }
      ];
    }
  ];
in
{
  _file = ./evdev-rules.nix;

  options.ghaf.hardware.passthrough.evdev = {
    evdevRules = mkOption {
      description = "Non-USB Input Device Passthrough Rules for GUIVM";
      type = types.listOf types.attrs;
      default = defaultEvdevRules;
    };
  };

  config = mkIf (config.ghaf.hardware.passthrough.mode != "none") {
    ghaf.hardware.passthrough.vhotplug.evdevRules =
      optionals config.ghaf.virtualization.microvm.guivm.enable cfg.evdevRules;
  };
}
