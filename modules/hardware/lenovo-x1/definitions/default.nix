# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  lib,
  ...
}: let
  hwDefinition = import (./. + "/x1-${config.ghaf.hardware.generation}.nix");
in {
  imports = [
    ../../definition.nix
  ];

  options.ghaf.hardware.generation = lib.mkOption {
    description = "Generation of the hardware configuration";
    type = lib.types.str;
    default = "gen11";
  };

  config = {
    ghaf.hardware.definition = {
      inherit (hwDefinition) mouse;
      inherit (hwDefinition) touchpad;
      inherit (hwDefinition) disks;
      inherit (hwDefinition) network;
      inherit (hwDefinition) gpu;

      virtioInputHostEvdevs = [
        # Lenovo X1 touchpad and keyboard
        "/dev/input/by-path/platform-i8042-serio-0-event-kbd"
        "/dev/input/by-path/platform-thinkpad_acpi-event"
        "/dev/mouse"
        "/dev/touchpad"
        # Lenovo X1 trackpoint (red button/joystick)
        "/dev/input/by-path/platform-i8042-serio-1-event-mouse"
      ];
    };

    disko.devices.disk = hwDefinition.disks;

    # Notes:
    #   1. This assembles udev rules for different hw configurations (i.e., different mice/touchpads) by adding
    #      all of them to the configuration. This was chosen for simplicity to not have to provide hw identifier at build,
    #      but is not ideal and should be changed.
    #   2. USB camera "passthrough" is handled by qemu and thus available on host. If peripheral VM is implemented,
    #      the entire host controller should be passthrough'd using the PCI bus (14.0). In x1, bluetooth and fingerprint
    #      reader are on this bus.
    services.udev.extraRules = ''
      # Laptop keyboard
      SUBSYSTEM=="input", ATTRS{name}=="AT Translated Set 2 keyboard", GROUP="kvm"
      # Laptop keyboard multimedia buttons
      SUBSYSTEM=="input", ATTRS{name}=="ThinkPad Extra Buttons", GROUP="kvm"
      # Laptop TrackPoint
      SUBSYSTEM=="input", ATTRS{name}=="TPPS/2 Elan TrackPoint", GROUP="kvm"
      # Lenovo X1 integrated webcam
      KERNEL=="3-8", SUBSYSTEM=="usb", ATTR{busnum}=="3", ATTR{devnum}=="3", GROUP="kvm"
      # Lenovo X1 integrated fingerprint reader
      KERNEL=="3-6", SUBSYSTEM=="usb", ATTR{busnum}=="3", ATTR{devnum}=="2", GROUP="kvm"
      # Mouse and Touchpad
      ${lib.strings.concatMapStringsSep "\n" (d: ''SUBSYSTEM=="input", ATTRS{name}=="${d}", KERNEL=="event*", GROUP="kvm", SYMLINK+="mouse"'') hwDefinition.mouse}
      ${lib.strings.concatMapStringsSep "\n" (d: ''SUBSYSTEM=="input", ATTRS{name}=="${d}", KERNEL=="event*", GROUP="kvm", SYMLINK+="touchpad"'') hwDefinition.touchpad}
    '';
  };
}
