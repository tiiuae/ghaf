# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# NET VM Hardware Passthrough Feature Module
#
# This module handles hardware-specific configurations for the NET VM:
# -
#
# These settings are host-bound and cannot be globalized, so they must
# come from hostConfig which is passed via specialArgs.
#
# Auto-enables when: hostConfig has network hardware devices
#
{
  lib,
  hostConfig,
  ...
}:
let
  # Get network devices config, defaulting to empty attrset
  netDevicesConfig = hostConfig.hardware.devices.nics or { };

  # Check if we have actual devices to passthrough (non-empty config)
  hasNetDevices = netDevicesConfig != { };

  # Get kernel/qemu configs (can be null)
  kernelConfig = hostConfig.kernel or null;
  qemuConfig = hostConfig.qemu or null;
in
{
  _file = ./hardware-passthrough.nix;

  config = lib.mkMerge (
    # Import nics device passthrough config from host
    lib.optional hasNetDevices netDevicesConfig
    # Kernel configuration from host (if defined)
    ++ lib.optional (kernelConfig != null) kernelConfig
    # QEMU configuration from host (if defined)
    ++ lib.optional (qemuConfig != null) qemuConfig
  );
}
