# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# GUI VM Hardware Passthrough Feature Module
#
# This module handles hardware-specific configurations for the GUI VM:
# - GPU device passthrough (from hostConfig.hardware.devices.gpus)
# - Input device passthrough (from hostConfig.hardware.devices.evdev)
# - Kernel configuration (from hostConfig.kernel — GPU modules in initrd, earlykms)
# - QEMU configuration (from hostConfig.qemu — laptop lid/battery/AC devices)
#
# These settings are host-bound and cannot be globalized, so they must
# come from hostConfig which is passed via specialArgs.
#
# Auto-enables when: hostConfig has GPU hardware devices
#
{
  lib,
  hostConfig,
  ...
}:
let
  # Get GPU devices config, defaulting to empty attrset
  gpuDevicesConfig = hostConfig.hardware.devices.gpus or { };

  # Get input devices config, defaulting to empty attrset
  evdevDevicesConfig = hostConfig.hardware.devices.evdev or { };

  # Check if we have actual devices to passthrough (non-empty config)
  hasGpuDevices = gpuDevicesConfig != { };
  hasEvdevDevices = evdevDevicesConfig != { };

  # Get kernel/qemu configs (can be null)
  kernelConfig = hostConfig.kernel or null;
  qemuConfig = hostConfig.qemu or null;
in
{
  _file = ./hardware-passthrough.nix;

  config = lib.mkMerge (
    # Import GPU device passthrough config from host
    lib.optional hasGpuDevices gpuDevicesConfig
    # Import input device passthrough config from host
    ++ lib.optional hasEvdevDevices evdevDevicesConfig
    # Kernel configuration from host (if defined)
    ++ lib.optional (kernelConfig != null) kernelConfig
    # QEMU configuration from host (if defined)
    ++ lib.optional (qemuConfig != null) qemuConfig
  );
}
