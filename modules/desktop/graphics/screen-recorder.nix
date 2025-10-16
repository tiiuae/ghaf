# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.graphics.screen-recorder;

  ghaf-screen-record = pkgs.writeShellApplication {
    name = "ghaf-screen-record";

    runtimeInputs = with pkgs; [
      gpu-screen-recorder
      libnotify
      killall
      xdg-utils
    ];

    text = ''
      # If gpu-screen-recorder is already running, stop it and exit
      if killall -SIGINT -q gpu-screen-recorder; then
          action=$(notify-send -h byte:urgency:0 -t 5000 -h "string:image-path:gpu-screen-recorder" -A "open=open" \
              -a "GPU Screen Recorder" "Screen recording stopped" "Screen recording saved to $HOME/Videos")
          # User clicked the notification
          if [ "$action" = "open" ]; then
              xdg-open "$HOME/Videos" &
          fi
          exit 0
      fi

      # Create output filename
      video="$HOME/Videos/ghaf-screen-capture_$(date +"%Y-%m-%d_%H-%M-%S").mp4"

      # Start recording
      if gpu-screen-recorder \
          -w portal \
          -c mp4 \
          -k h264 \
          -ac opus \
          -f 60 \
          -cursor yes \
          -restore-portal-session yes \
          -cr limited \
          -encoder gpu \
          -q very_high \
          -a device:default_output \
          -o "$video" &
      then
          notify-send -h byte:urgency:0 -t 5000 -h "string:image-path:gpu-screen-recorder" -a "GPU Screen Recorder" \
              "Screen recording started" "Use CTRL+SHIFT+ALT+R to stop recording"
      else
          notify-send -h byte:urgency:0 -t 5000 -h "string:image-path:gpu-screen-recorder" -a "GPU Screen Recorder" \
              "Screen recording failed" "Failed to start screen recording"
          exit 1
      fi
    '';
  };
in
{
  options.ghaf.graphics.screen-recorder = {
    enable = lib.mkEnableOption "Whether to enable screen recording capabilities using gpu-screen-recorder.";
  };

  config = lib.mkIf cfg.enable {
    # OBS is another option to capture the screen in Cosmic
    # Other options include Kooha and Wayfarer, but are misbehaving as of Cosmic Alpha 7
    # due to issues with the xdg-desktop-portal-cosmic implementation
    # ref. https://github.com/SeaDve/Kooha/issues/311
    # programs.obs-studio.enable = true;

    # XDG desktop portal screen capture requires pipewire and wireplumber to be enabled
    services.pipewire = {
      enable = true;
      wireplumber.enable = true;
    };

    environment.systemPackages = with pkgs; [
      gpu-screen-recorder
      # UI for gpu-screen-recorder
      gpu-screen-recorder-gtk

      # Script to start/stop screen recording
      ghaf-screen-record
    ];

    assertions = [
      {
        assertion = pkgs.stdenv.isx86_64;
        message = "GPU screen recording is only supported on x86_64";
      }
    ];
  };
}
