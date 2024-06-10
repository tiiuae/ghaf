# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  lib,
  ...
}: let
  hwDefinition = import (./. + "/definitions/x1-${config.ghaf.hardware.generation}.nix");
  inherit (lib) mkOption types;
in {
  imports = [
    ../definition.nix
  ];

  options.ghaf.hardware.generation = mkOption {
    description = "Generation of the hardware configuration";
    type = types.nullOr types.str;
    default = null;
  };

  config = {
    # Hardware definition
    ghaf.hardware.definition = {
      inherit (hwDefinition) generic;
      inherit (hwDefinition) input;
      inherit (hwDefinition) disks;
      inherit (hwDefinition) network;
      inherit (hwDefinition) gpu;
      inherit (hwDefinition) audio;
      inherit (hwDefinition) usb;
    };

    # Disk configuration
    disko.devices.disk = hwDefinition.disks;

    # Hardware specific kernel parameters
    boot = {
      inherit (hwDefinition.generic) kernelParams;
    };

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
