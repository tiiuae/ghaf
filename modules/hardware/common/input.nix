# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ config, lib, ... }:
let
  inherit (builtins) toString typeOf;
  inherit (lib) concatImapStrings concatMapStringsSep;

  cfg = config.ghaf.hardware.definition;

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
  config = {
    # Disk configuration
    # TODO Remove or move this
    disko.devices.disk = cfg.disks;

    # Host udev rules for input devices
    services.udev.extraRules = ''
      # Keyboard
      ${generateUdevRules "keyboard" cfg.input.keyboard.name}
      # Mouse
      ${generateUdevRules "mouse" cfg.input.mouse.name}
      # Touchpad
      ${generateUdevRules "touchpad" cfg.input.touchpad.name}
      # Misc
      ${lib.strings.concatMapStringsSep "\n" (
        d: ''SUBSYSTEM=="input", ATTRS{name}=="${d}", GROUP="kvm"''
      ) cfg.input.misc.name}
    '';
  };
}
