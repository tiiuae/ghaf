# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Turn on COSMIC's "show on-screen keyboard when selecting a text field" while
# the device has a touchscreen and no usable keyboard (none attached, or folded
# into tablet mode). A manual change sticks until that detection flips again.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  # Desktop users are not in the input group, so detection runs as root and
  # publishes the result here for the per-user service to apply.
  stateFile = "/run/ghaf-osk-auto/ime-activation";

  detect = pkgs.writeShellApplication {
    name = "ghaf-osk-auto-detect";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.systemd
      pkgs.evtest
      pkgs.libinput
    ];
    text = ''
      detect() {
        local touch=false keyboard=false tablet=false want=false rc props dev
        for dev in /sys/class/input/event*; do
          props=$(udevadm info -q property -p "$dev" 2>/dev/null) || continue
          grep -qx ID_INPUT_TOUCHSCREEN=1 <<<"$props" && touch=true
          grep -qx ID_INPUT_KEYBOARD=1 <<<"$props" && keyboard=true
          if grep -qx ID_INPUT_SWITCH=1 <<<"$props"; then
            rc=0
            evtest --query "/dev/input/''${dev##*/}" EV_SW SW_TABLET_MODE || rc=$?
            # evtest --query exits 10 when the switch is set.
            [ "$rc" -eq 10 ] && tablet=true
          fi
        done
        if $touch && { ! $keyboard || $tablet; }; then
          want=true
        fi
        if [ "$(cat ${stateFile} 2>/dev/null)" != "$want" ]; then
          echo "touchscreen=$touch keyboard=$keyboard tablet-mode=$tablet: ime_activation=$want"
          printf '%s' "$want" >${stateFile}
        fi
      }

      detect
      stdbuf -oL libinput debug-events | while read -r line; do
        case "$line" in
          *DEVICE_ADDED* | *DEVICE_REMOVED* | *SWITCH_TOGGLE*) detect ;;
        esac
      done
    '';
  };

  apply = pkgs.writeShellApplication {
    name = "ghaf-osk-auto-apply";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      want=$(cat ${stateFile} 2>/dev/null) || exit 0
      state=''${XDG_STATE_HOME:-$HOME/.local/state}
      marker=$state/ghaf/osk-ime-activation
      # Only act on a change in detection, so a manual setting is kept.
      [ "$(cat "$marker" 2>/dev/null)" = "$want" ] && exit 0
      mkdir -p "$state/cosmic/com.system76.CosmicOSK/v1" "$state/ghaf"
      printf '%s' "$want" >"$state/cosmic/com.system76.CosmicOSK/v1/ime_activation"
      printf '%s' "$want" >"$marker"
    '';
  };
in
{
  _file = ./osk-auto.nix;

  config = lib.mkIf config.ghaf.graphics.cosmic.enable {
    systemd.services.ghaf-osk-auto = {
      description = "Detect touch-only input for the COSMIC on-screen keyboard";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = lib.getExe detect;
        RuntimeDirectory = "ghaf-osk-auto";
        RuntimeDirectoryMode = "0755";
        Restart = "on-failure";
      };
    };

    systemd.user.services.ghaf-osk-auto = {
      description = "Apply touch-only input detection to the COSMIC on-screen keyboard";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe apply;
      };
      wantedBy = [ "cosmic-session.target" ];
    };

    systemd.user.paths.ghaf-osk-auto = {
      description = "Watch touch-only input detection";
      pathConfig.PathChanged = stateFile;
      wantedBy = [ "cosmic-session.target" ];
    };
  };
}
