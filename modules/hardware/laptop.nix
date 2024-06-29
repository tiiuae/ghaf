# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.hardware.definition;
  hwDefinition = import (./. + cfg.configFile);
  inherit (lib) mkOption types;
in {
  imports = [
    ./definition.nix
  ];

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

    # Host udev rules
    services.udev.extraRules = ''
      # Keyboard
      ${lib.strings.concatMapStringsSep "\n" (d: ''SUBSYSTEM=="input", ATTRS{name}=="${d}", GROUP="kvm"'') hwDefinition.input.keyboard.name}
      # Mouse
      ${lib.strings.concatMapStringsSep "\n" (d: ''SUBSYSTEM=="input", ATTRS{name}=="${d}", KERNEL=="event*", GROUP="kvm", SYMLINK+="mouse"'') hwDefinition.input.mouse.name}
      # Touchpad
      ${lib.strings.concatMapStringsSep "\n" (d: ''SUBSYSTEM=="input", ATTRS{name}=="${d}", KERNEL=="event*", GROUP="kvm", SYMLINK+="touchpad"'') hwDefinition.input.touchpad.name}
      # Other
      ${lib.strings.concatMapStringsSep "\n" (d: ''SUBSYSTEM=="input", ATTRS{name}=="${d}", GROUP="kvm"'') hwDefinition.input.misc.name}
    '';
  };
}
