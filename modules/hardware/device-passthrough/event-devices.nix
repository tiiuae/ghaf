# Copyright 2025-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{ config, lib, ... }:
let
  inherit (lib) mkOption types mkIf;
  cfg = config.ghaf.hardware.passthrough.eventDevices;
  qemuExtraArgsEvt = {
    "${cfg.targetVM}" = builtins.concatMap (n: [
      "-device"
      "pcie-root-port,bus=pcie.0,id=${cfg.pcieBusPrefix}${toString n},chassis=${toString n}"
    ]) (lib.range 1 cfg.pciePortCount);
  };
in
{
  options.ghaf.hardware.passthrough.eventDevices = {
    targetVM = mkOption {
      type = types.str;
      default = "gui-vm";
      description = ''
        VM to passthrough event device.
      '';
    };

    pcieBusPrefix = mkOption {
      type = types.nullOr types.str;
      default = "rp";
      description = ''
        PCIe bus prefix used for the pcie-root-port QEMU device when evdev passthrough is enabled.
      '';
    };

    pciePortCount = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = ''
        The number of PCIe ports used for hot-plugging virtio-input-host-pci devices.
      '';
    };
  };

  #config = mkIf (config.ghaf.hardware.passthrough.mode == "static") {
  config = mkIf (config.ghaf.hardware.passthrough.mode != "none") {
    ghaf.hardware.passthrough = {
      qemuExtraArgs = qemuExtraArgsEvt;
    };
  };
}
