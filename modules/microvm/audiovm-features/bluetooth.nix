# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Audio VM Bluetooth Feature Module
#
# This module enables Bluetooth service in the Audio VM when bluetooth feature
# is enabled for this VM.
#
# Auto-enables when: globalConfig.features.bluetooth enabled for this VM
#
{
  lib,
  globalConfig,
  ...
}:
let
  vmName = "audio-vm";
  # Check if bluetooth feature is enabled for this VM
  bluetoothEnabled = lib.ghaf.features.isEnabledFor globalConfig "bluetooth" vmName;
in
{
  _file = ./bluetooth.nix;

  config = lib.mkIf bluetoothEnabled {
    ghaf.services.bluetooth.enable = true;
  };
}
