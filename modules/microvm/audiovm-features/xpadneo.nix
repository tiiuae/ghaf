# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Audio VM Xpadneo Feature Module
#
# This module configures Xbox controller support (xpadneo) in the Audio VM.
# Currently disabled by default but available for future use.
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
  _file = ./xpadneo.nix;

  config = lib.mkIf audioEnabled {
    # Xpadneo is currently disabled (matches modules.nix behavior)
    ghaf.services.xpadneo.enable = false;
  };
}
