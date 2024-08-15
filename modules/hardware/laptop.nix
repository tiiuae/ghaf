# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ config, lib, ... }:
let
  inherit (builtins) toString typeOf;
  inherit (lib)
    mkOption
    types
    concatImapStrings
    concatMapStringsSep
    ;

  cfg = config.ghaf.hardware.definition;
  hwDefinition = import (./. + cfg.configFile);

  # Helper function to create udev rules for input devices
  generateUdevRules =
    devlink: deviceList:
    concatImapStrings (
      i: d:
      if (typeOf d) == "list" then
        ''${
          concatMapStringsSep "\n" (
            sd:
            ''SUBSYSTEM=="input", ATTRS{name}=="${sd}", KERNEL=="event*", GROUP="kvm", SYMLINK+="${devlink}${toString (i - 1)}"''
          ) d
        }''\n''
      else
        ''SUBSYSTEM=="input", ATTRS{name}=="${d}", KERNEL=="event*", GROUP="kvm", SYMLINK+="${devlink}${toString (i - 1)}"''\n''
    ) deviceList;
in
{
  imports = [ ./definition.nix ];

  options.ghaf.hardware.definition.configFile = mkOption {
    description = "Path to the hardware configuration file.";
    type = types.str;
    default = "";
  };

  config = {
    # Hardware definition
    ghaf.hardware.definition = {
      inherit (hwDefinition) host;
      inherit (hwDefinition) input;
      inherit (hwDefinition) disks;
      inherit (hwDefinition) network;
      inherit (hwDefinition) gpu;
      inherit (hwDefinition) audio;
      inherit (hwDefinition) usb;
    };

    # Disk configuration
    disko.devices.disk = hwDefinition.disks;

    # Host udev rules for input devices
    services.udev.extraRules = ''
      # Keyboard
      ${generateUdevRules "keyboard" hwDefinition.input.keyboard.name}
      # Mouse
      ${generateUdevRules "mouse" hwDefinition.input.mouse.name}
      # Touchpad
      ${generateUdevRules "touchpad" hwDefinition.input.touchpad.name}
      # Misc
      ${lib.strings.concatMapStringsSep "\n" (
        d: ''SUBSYSTEM=="input", ATTRS{name}=="${d}", GROUP="kvm"''
      ) hwDefinition.input.misc.name}
    '';
  };
}
