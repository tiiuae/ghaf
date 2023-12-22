# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  generation,
  lib,
}: let
  hwDefinition = import (./. + "/x1-${generation}.nix");
in {
  inherit (hwDefinition) mouse;
  inherit (hwDefinition) touchpad;
  inherit (hwDefinition) disks;
  inherit (hwDefinition) network;
  inherit (hwDefinition) gpu;

  # Notes:
  #   1. This assembles udev rules for different hw configurations (i.e., different mice/touchpads) by adding
  #      all of them to the configuration. This was chosen for simplicity to not have to provide hw identifier at build,
  #      but is not ideal and should be changed.
  #   2. USB camera "passthrough" is handled by qemu and thus available on host. If peripheral VM is implemented,
  #      the entire host controller should be passthrough'd using the PCI bus (14.0). In x1, bluetooth and fingerprint
  #      reader are on this bus.
  udevRules = let
    mapMouseRules =
      builtins.map (d: ''        SUBSYSTEM=="input", ATTRS{name}=="${d}", KERNEL=="event*", GROUP="kvm", SYMLINK+="mouse"
      '');
    mapTouchpadRules =
      builtins.map (d: ''        SUBSYSTEM=="input", ATTRS{name}=="${d}", KERNEL=="event*", GROUP="kvm", SYMLINK+="touchpad"
      '');
  in ''
    # Laptop keyboard
    SUBSYSTEM=="input", ATTRS{name}=="AT Translated Set 2 keyboard", GROUP="kvm"
    # Laptop TrackPoint
    SUBSYSTEM=="input", ATTRS{name}=="TPPS/2 Elan TrackPoint", GROUP="kvm"
    # Lenovo X1 integrated webcam
    KERNEL=="3-8", SUBSYSTEM=="usb", ATTR{busnum}=="3", ATTR{devnum}=="3", GROUP="kvm"
    # External USB GPS receiver
    SUBSYSTEM=="usb", ATTR{idVendor}=="067b", ATTR{idProduct}=="23a3", GROUP="kvm"
    # Mouse and Touchpad
    ${lib.strings.concatStrings (mapMouseRules hwDefinition.mouse)}
    ${lib.strings.concatStrings (mapTouchpadRules hwDefinition.touchpad)}
  '';

  virtioInputHostEvdevs = [
    # Lenovo X1 touchpad and keyboard
    "/dev/input/by-path/platform-i8042-serio-0-event-kbd"
    "/dev/mouse"
    "/dev/touchpad"
    # Lenovo X1 trackpoint (red button/joystick)
    "/dev/input/by-path/platform-i8042-serio-1-event-mouse"
  ];
}
