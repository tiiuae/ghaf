# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Audio VM Xpadneo Feature Module
#
# This module configures Xbox controller support (xpadneo) in the Audio VM.
# Currently disabled by default but available for future use.
#
# Auto-enables when: globalConfig.features.audio enabled for this VM
#
{
  lib,
  globalConfig,
  ...
}:
let
  vmName = "audio-vm";
  # Check if audio feature is enabled for this VM
  audioEnabled = lib.ghaf.features.isEnabledFor globalConfig "audio" vmName;
in
{
  _file = ./xpadneo.nix;

  config = lib.mkIf audioEnabled {
    # Xpadneo is currently disabled (matches modules.nix behavior)
    ghaf.services.xpadneo.enable = false;
  };
}
