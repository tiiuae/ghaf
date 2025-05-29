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
  uid = builtins.toString config.ghaf.users.loginUser.uid;
in
{
  options.ghaf.services.acpid = {
    enable = mkEnableOption "Enable lid event handling via acpid";
  };

  config = mkIf cfg.enable {
    services.acpid = {
      enable = true;
      lidEventCommands = ''
        wl_running=1
        case "$1" in
          "button/lid LID close")
            ${pkgs.systemd}/bin/loginctl lock-sessions
            if ${pkgs.procps}/bin/pgrep -fl "wayland" > /dev/null; then
              wl_running=1
              WAYLAND_DISPLAY=/run/user/${uid}/wayland-0 ${pkgs.wlopm}/bin/wlopm --off '*'
            else
              wl_running=0
            fi
            ${lib.optionalString config.ghaf.profiles.graphics.allowSuspend ''
              ${pkgs.givc-cli}/bin/givc-cli ${config.ghaf.givc.cliArgs} suspend
              if [ "$wl_running" -eq 1 ]; then
                WAYLAND_DISPLAY=/run/user/${uid}/wayland-0 ${pkgs.wlopm}/bin/wlopm --on '*'
              fi
            ''}
            ;;
          "button/lid LID open")
            ${lib.optionalString (!config.ghaf.profiles.graphics.allowSuspend) ''
              if [ "$wl_running" -eq 1 ]; then
                WAYLAND_DISPLAY=/run/user/${uid}/wayland-0 ${pkgs.wlopm}/bin/wlopm --on '*'
              fi
            ''}
            ;;
        esac
      '';
    };
  };
}
