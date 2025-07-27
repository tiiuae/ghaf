# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This service runs before any of the microvms, detects devices for passthrough and sets up VFIO bindings
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.microvm.vhwdetect;
  inherit (lib)
    mkEnableOption
    mkIf
    ;
in
{
  options.ghaf.microvm.vhwdetect = {
    enable = mkEnableOption "Enable hardware detection for passthrough to virtual machines";
  };

  config = mkIf cfg.enable {

    services.udev.extraRules = ''
      SUBSYSTEM=="vfio",GROUP="kvm"
    '';

    boot.kernelModules = [ "vfio-pci" ];

    systemd.services.vhwdetect-vfio = {
      enable = true;
      description = "vhwdetect-vfio";
      wantedBy = [ "microvms.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.vhwdetect}/bin/vhwdetect --vfio-setup --devices display audio network";
      };
      startLimitIntervalSec = 0;
    };

    systemd.services."microvm@".after = [ "vhwdetect-vfio.service" ];
  };
}
