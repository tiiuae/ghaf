# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.hardware.nvidia.passthroughs.host.uarta;
in
{
  _file = ./default.nix;

  options.ghaf.hardware.nvidia.passthroughs.host.uarta.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable UARTA passthrough on Nvidia Orin host";
  };

  config = lib.mkIf cfg.enable {
    ghaf.hardware.nvidia.virtualization = {
      enable = true;
      host.bpmp.enable = true;
    };

    systemd.services = {
      enableVfioPlatform = {
        description = "Enable the vfio-platform driver for UARTA";
        wantedBy = [ "bindSerial3100000.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = "yes";
          ExecStart = ''
            ${pkgs.bash}/bin/bash -c "echo vfio-platform > /sys/bus/platform/devices/3100000.serial/driver_override"
          '';
        };
      };

      bindSerial3100000 = {
        description = "Bind UARTA to the vfio-platform driver";
        wantedBy = [ "multi-user.target" ];
        after = [ "enableVfioPlatform.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = "yes";
          ExecStart = ''
            ${pkgs.bash}/bin/bash -c "echo 3100000.serial > /sys/bus/platform/drivers/vfio-platform/bind"
          '';
        };
      };
    };
  };
}
