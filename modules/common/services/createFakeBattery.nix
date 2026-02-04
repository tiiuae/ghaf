# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf mkEnableOption;

  cfg = config.ghaf.services.create-fake-battery;
in
{
  _file = ./createFakeBattery.nix;

  options.ghaf.services.create-fake-battery = {
    enable = mkEnableOption "Create a fake battery device for VMs";
  };

  config =
    mkIf
      (
        cfg.enable
        && (
          (builtins.hasAttr "definition" config.ghaf.hardware)
          && config.ghaf.hardware.definition.type == "laptop"
        )
      )
      {

        systemd.services."create-fake-battery" = {
          description = "Create fake battery if not present";
          wantedBy = [ "basic.target" ];
          after = [ "basic.target" ];
          unitConfig.ConditionPathExists = "!/sys/class/power_supply/BAT0";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkgs.kmod}/bin/modprobe fake_battery";
          };
        };
      };
}
