# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;
  cfg = config.ghaf.services.acpid;
  ghaf-powercontrol = pkgs.ghaf-powercontrol.override { ghafConfig = config.ghaf; };
in
{
  options.ghaf.services.acpid = {
    enable = mkEnableOption "lid event handling via acpid";
  };

  config = mkIf cfg.enable {
    services.acpid = {
      enable = true;
      lidEventCommands = lib.mkIf config.ghaf.profiles.graphics.allowSuspend ''
        case "$1" in
          "button/lid LID close")
            AC_DEVICE=$(${lib.getExe pkgs.upower} -e | ${lib.getExe pkgs.gnugrep} 'line.*power')
            if ${lib.getExe pkgs.upower} -i "$AC_DEVICE" | ${lib.getExe pkgs.gnugrep} -q 'online:\s*yes'; then
              ${lib.getExe ghaf-powercontrol} turn-off-displays eDP-1
            else
              ${lib.getExe ghaf-powercontrol} suspend
            fi
            ;;
          "button/lid LID open")
            ${lib.getExe ghaf-powercontrol} wakeup
            ;;
        esac
      '';
    };
  };
}
