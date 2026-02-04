# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Audio VM Hardware Passthrough Feature Module
#
# This module handles hardware-specific configurations for the Audio VM:
# - Audio device passthrough (from hostConfig.hardware.devices.audio)
# - Kernel configuration (from hostConfig.kernel)
# - QEMU configuration (from hostConfig.qemu)
#
# These settings are host-bound and cannot be globalized, so they must
# come from hostConfig which is passed via specialArgs.
#
# Auto-enables when: hostConfig has audio hardware devices
#
{
  lib,
  hostConfig,
  ...
}:
let
  # Check if we have audio hardware devices to passthrough
  hasAudioDevices = (hostConfig.hardware.devices.audio or null) != null;

  # Check if we have kernel config for audiovm
  hasKernelConfig = (hostConfig.kernel or null) != null;

  # Check if we have qemu config for audiovm
  hasQemuConfig = (hostConfig.qemu or null) != null;
in
{
  _file = ./hardware-passthrough.nix;

  config = lib.mkMerge [
    # Import audio device passthrough config from host (as config values, not imports)
    (lib.mkIf hasAudioDevices hostConfig.hardware.devices.audio)

    # Kernel configuration from host
    (lib.mkIf hasKernelConfig hostConfig.kernel)

    # QEMU configuration from host
    (lib.mkIf hasQemuConfig hostConfig.qemu)
  ];
}
