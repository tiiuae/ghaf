# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Audio VM Bluetooth Feature Module
#
# This module enables Bluetooth service in the Audio VM when audio hardware
# passthrough is enabled.
#
# Auto-enables when: hostConfig.audiovm.audio == true
#
{
  lib,
  hostConfig,
  ...
}:
let
  # Check if audio hardware passthrough is enabled
  audioEnabled = hostConfig.audiovm.audio or false;
in
{
  _file = ./bluetooth.nix;

  config = lib.mkIf audioEnabled {
    ghaf.services.bluetooth.enable = true;
  };
}
