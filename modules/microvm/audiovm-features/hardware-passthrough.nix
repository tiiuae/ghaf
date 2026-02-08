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
  # Get audio devices config, defaulting to empty attrset
  audioDevicesConfig = hostConfig.hardware.devices.audio or { };

  # Check if we have actual audio devices to passthrough (non-empty config)
  hasAudioDevices = audioDevicesConfig != { };

  # Get kernel/qemu configs (can be null)
  kernelConfig = hostConfig.kernel or null;
  qemuConfig = hostConfig.qemu or null;
in
{
  _file = ./hardware-passthrough.nix;

  config = lib.mkMerge (
    # Import audio device passthrough config from host
    lib.optional hasAudioDevices audioDevicesConfig
    # Kernel configuration from host (if defined)
    ++ lib.optional (kernelConfig != null) kernelConfig
    # QEMU configuration from host (if defined)
    ++ lib.optional (qemuConfig != null) qemuConfig
  );
}
