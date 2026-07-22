# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Peripherals VM Hardware Passthrough Feature Module
#
# This module handles hardware-specific configurations for the Peripherals VM:
# - USB device passthrough
#
# These settings are host-bound and cannot be globalized, so they must
# come from hostConfig which is passed via specialArgs.
#
# Auto-enables when: hostConfig has USB hardware devices
#
{
  lib,
  hostConfig,
  ...
}:
let
  # Get USB controllers config, defaulting to empty attrset
  usbControllersConfig = hostConfig.hardware.devices.usbControllers or { };

  # Check if we have actual devices to passthrough (non-empty config)
  hasUsbControllers = usbControllersConfig != { };

  # Get kernel/qemu configs (can be null)
  kernelConfig = hostConfig.kernel or null;
  qemuConfig = hostConfig.qemu or null;
in
{
  _file = ./hardware-passthrough.nix;

  config = lib.mkMerge (
    # Import USB controller passthrough config from host
    lib.optional hasUsbControllers usbControllersConfig
    # Kernel configuration from host (if defined)
    ++ lib.optional (kernelConfig != null) kernelConfig
    # QEMU configuration from host (if defined)
    ++ lib.optional (qemuConfig != null) qemuConfig
  );
}
