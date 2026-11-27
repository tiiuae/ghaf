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

  # Tray: COSMIC's record dot, forced red; a -symbolic name would be recoloured by the panel.
  # Launcher: Papirus's screen recorder icon.
  icons = pkgs.runCommand "ghaf-screen-record-icons" { } ''
    install -Dm644 ${pkgs.cosmic-icons}/share/icons/Cosmic/scalable/actions/media-record-symbolic.svg \
      $out/share/icons/hicolor/scalable/status/ghaf-screen-recording.svg
    substituteInPlace $out/share/icons/hicolor/scalable/status/ghaf-screen-recording.svg \
      --replace-fail 'fill="#232323"' 'fill="#e01b24"'
    install -Dm644 ${pkgs.papirus-icon-theme}/share/icons/Papirus/64x64/apps/com.github.mohelm97.screenrecorder.svg \
      $out/share/icons/hicolor/scalable/apps/ghaf-screen-record.svg
  '';

  recordDesktopItem = pkgs.makeDesktopItem {
    name = "ghaf-screen-record";
    desktopName = "Record Screen";
    comment = "Start or stop a screen recording (Ctrl+Shift+Alt+R)";
    exec = "ghaf-screen-record";
    icon = "ghaf-screen-record";
    categories = [
      "AudioVideo"
      "Recorder"
    ];
  };

  # Utility moves it from the app library's Home into its Utilities group
  gpu-screen-recorder-gtk = pkgs.gpu-screen-recorder-gtk.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      substituteInPlace $out/share/applications/com.dec05eba.gpu_screen_recorder.desktop \
        --replace-fail "Categories=AudioVideo;Recorder;" "Categories=AudioVideo;Recorder;Utility;"
    '';
  });

  trayConfig = (pkgs.formats.toml { }).generate "screen-recording-tray.toml" {
    icon = "ghaf-screen-recording";
    title = "Screen recording";
    entry = [
      {
        type = "label";
        id = "status";
        label = "Recording";
      }
      {
        id = "pause";
        label = "Pause";
        icon = "media-playback-pause-symbolic";
        command = "ghaf-screen-record pause";
      }
      {
        id = "stop";
        label = "Stop recording";
        icon = "media-playback-stop-symbolic";
        exit = true;
      }
    ];
    exit = {
      id = "discard";
      label = "Discard recording";
      icon = "user-trash-symbolic";
      signal = "INT";
    };
  };

  ghaf-screen-record = pkgs.writeShellApplication {
    name = "ghaf-screen-record";

    runtimeInputs = with pkgs; [
      gnugrep
      gpu-screen-recorder
      libnotify
      killall
      trayler
      util-linux
      xdg-utils
    ];

    text = ''
      socket="$XDG_RUNTIME_DIR/ghaf-screen-record.sock"
      paused="$XDG_RUNTIME_DIR/ghaf-screen-record.paused"

      # Called from the tray's Pause/Resume entry
      if [ "''${1:-}" = pause ]; then
          if [ -e "$paused" ]; then
              gsr-cli -ipc "$socket" set-paused false
              rm -f "$paused"
              trayler ctl "$TRAYLER_CONTROL" set status label=Recording
              trayler ctl "$TRAYLER_CONTROL" set pause label=Pause icon=media-playback-pause-symbolic
          else
              gsr-cli -ipc "$socket" set-paused true
              touch "$paused"
              trayler ctl "$TRAYLER_CONTROL" set status label=Paused
              trayler ctl "$TRAYLER_CONTROL" set pause label=Resume icon=media-playback-start-symbolic
          fi
          exit 0
      fi

      # Ignore presses while a previous one is still starting the recording
      exec 9>"$XDG_RUNTIME_DIR/ghaf-screen-record.lock"
      flock -n 9 || exit 0

      # If gpu-screen-recorder is already running, stop it; the tray reports the stop
      if killall -SIGINT -q gpu-screen-recorder; then
          exit 0
      fi

      # Create output filename
      mkdir -p "$HOME/Videos"
      video="$HOME/Videos/ghaf-screen-capture_$(date +"%Y-%m-%d_%H-%M-%S").mkv"
      log="$XDG_RUNTIME_DIR/ghaf-screen-record.log"
      rm -f "$paused"

      # Start recording
      gpu-screen-recorder \
          -w portal \
          -c mkv \
          -k h264 \
          -ac opus \
          -f 60 \
          -cursor yes \
          -cr limited \
          -encoder gpu \
          -q very_high \
          -a device:default_output \
          -ipc "$socket" \
          -o "$video" 9>&- 2>"$log" &
      recorder=$!

      # Recording starts once the portal picker is accepted
      while kill -0 "$recorder" 2>/dev/null; do
          if grep -q "pipewire setup finished" "$log"; then
              notify-send -h byte:urgency:0 -t 5000 -h "string:image-path:com.dec05eba.gpu_screen_recorder" -a "GPU Screen Recorder" \
                  "Screen recording started" "Use CTRL+SHIFT+ALT+R or the tray icon to stop recording"
              # trayler returns when the recorder exits, however it was stopped
              (
                  # Prints the id of the menu entry that ended the recording
                  ended=$(trayler --config ${trayConfig} --control "$XDG_RUNTIME_DIR/ghaf-screen-record-tray.sock" \
                      --pid "$recorder")
                  if [ "$ended" = discard ]; then
                      rm -f "$video"
                      notify-send -h byte:urgency:0 -t 5000 -h "string:image-path:com.dec05eba.gpu_screen_recorder" -a "GPU Screen Recorder" \
                          "Screen recording discarded" "The recording was not saved"
                      exit 0
                  fi
                  action=$(notify-send -h byte:urgency:0 -t 5000 -h "string:image-path:com.dec05eba.gpu_screen_recorder" -A "open=open" \
                      -a "GPU Screen Recorder" "Screen recording stopped" "Screen recording saved to $HOME/Videos")
                  if [ "$action" = "open" ]; then
                      xdg-open "$HOME/Videos"
                  fi
              ) 9>&- &
              exit 0
          fi
          sleep 0.2
      done

      # 60 means the portal picker was cancelled
      rc=0
      wait "$recorder" || rc=$?
      if [[ $rc -ne 0 && $rc -ne 60 ]]; then
          notify-send -h byte:urgency:0 -t 5000 -h "string:image-path:com.dec05eba.gpu_screen_recorder" -a "GPU Screen Recorder" \
              "Screen recording failed" "Failed to start screen recording"
          exit 1
      fi
    '';
  };
in
{
  _file = ./screen-recorder.nix;

  options.ghaf.graphics.screen-recorder.enable =
    lib.mkEnableOption "screen recording capabilities using gpu-screen-recorder";

  config = lib.mkIf cfg.enable {
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
      icons
      recordDesktopItem
    ];

    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isx86_64;
        message = "GPU screen recording is only supported on x86_64";
      }
    ];
  };
}
