# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ config, lib, ... }:
let
  cfg = config.ghaf.hardware.definition;
in
{
  _file = ./input.nix;

  config = {
    # Host udev rules for input devices
    services.udev.extraRules = ''
      # Misc
      ${lib.strings.concatMapStringsSep "\n" (
        d: ''SUBSYSTEM=="input", ATTRS{name}=="${d}", GROUP="kvm"''
      ) cfg.input.misc.name}
    '';
  };
}
