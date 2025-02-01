# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.ghaf.services.audio;
  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;
in
{
  options.ghaf.services.audio = {
    enable = mkEnableOption "Enable audio service for audio VM";
    pulseaudioTcpPort = mkOption {
      type = types.int;
      default = 4713;
      description = "TCP port used by Pipewire-pulseaudio service";
    };
    pulseaudioTcpControlPort = mkOption {
      type = types.int;
      default = 4714;
      description = "TCP port used by Pipewire-pulseaudio control";
    };
    pulseaudioUnixSocketPath = mkOption {
      type = types.path;
      default = "/run/pipewire/pulseaudio-0";
      description = "Path to Unix socket used by Pipewire-pulseaudio service";
    };
    pulseaudioUseShmem = mkOption {
      type = types.bool;
      default = false;
      description = "Use shared memory for audio service";
    };
  };

  config = mkIf cfg.enable {
    # Enable pipewire service for audioVM with pulseaudio support
    security.rtkit.enable = true;
    hardware.firmware = [ pkgs.sof-firmware ];
    services.pipewire = {
      enable = true;
      pulse.enable = true;
      alsa.enable = config.ghaf.development.debug.tools.enable;
      systemWide = true;
      extraConfig = {
        pipewire."10-remote-pulseaudio" = {
          "context.modules" = [
            {
              name = "libpipewire-module-protocol-pulse";
              args = {
                # Enable Unix or TCP socket for VMs pulseaudio clients
                "server.address" = [
                  {
                    address =
                      if cfg.pulseaudioUseShmem then
                        "unix:${cfg.pulseaudioUnixSocketPath}"
                      else
                        "tcp:0.0.0.0:${toString cfg.pulseaudioTcpPort}";
                    "client.access" = "restricted";
                  }
                ];
                "pulse.min.req" = "1024/48000";
                "pulse.min.quantum" = "1024/48000";
                "pulse.idle.timeout" = "3";
              };
            }
            {
              name = "libpipewire-module-protocol-pulse";
              args = {
                # Enable TCP socket for VMs pulseaudio clients
                "server.address" = [
                  {
                    address = "tcp:0.0.0.0:${toString cfg.pulseaudioTcpControlPort}";
                    "client.access" = "unrestricted";
                  }
                ];
              };
            }
          ];
        };
      };
      # Disable the auto-switching to the low-quality HSP profile
      wireplumber.extraConfig.disable-autoswitch = {
        "wireplumber.settings" = {
          "bluetooth.autoswitch-to-headset-profile" = "false";
        };
      };
    };

    # Start pipewire on system boot
    systemd.services.pipewire.wantedBy = [ "multi-user.target" ];

    systemd.services."initialize-audio-profile" =
      let
        initialize-audio-profile = pkgs.writeShellApplication {
          name = "initialize-audio-profile";
          runtimeInputs = [
            pkgs.pulseaudio
            pkgs.jq
          ];
          text = ''
            function setProfile() {
              if [[ -n "$1" ]] && [[ -n "$2" ]]; then
                echo "Setting audio device profile: ($1 - $2)"
                pactl set-card-profile "$1" "$2"
              fi
            }

            function findAudioProfiles() {
              local audio_device_name active_profile profile_list
              if [[ -n "$1" ]]; then
                audio_device_name=$(jq --raw-output --argjson index "$1" '.[$index].name' <<< "$pactl_data")
                active_profile=$(jq --raw-output --argjson index "$1" '.[$index].active_profile ' <<< "$pactl_data")
                if [[ -n "$audio_device_name" ]]; then
                  echo "Found the default audio device: $audio_device_name"
                  profile_list=$(jq --raw-output --argjson index "$1" '.[$index].profiles | keys[]' <<< "$pactl_data")
                  echo "With profiles: $profile_list"
                  while IFS= read -r profile; do
                    setProfile "$audio_device_name" "$profile"
                  done <<< "$profile_list"

                  echo "Reset the original active profile."
                  if [[ -n "$active_profile" ]]; then
                    setProfile "$audio_device_name" "$active_profile"
                  fi
                fi
              fi
            }

            pactl_data=$(pactl --format=json list cards)
            if [[ -z "$pactl_data" ]]; then
              pulse_address="''${PULSE_SERVER:-localhost}"
              echo "Error connecting to Pulseaudio service at: \"$pulse_address\""
              exit 1
            fi

            default_device_id=$(pactl --format=json info short | jq '.default_sink_name | split(".") | .[1:-1] | join(".")')
            echo "Default audio device name: $default_device_id";

            audio_device_count=$(jq '. | length' <<< "$pactl_data")
            echo "Audio device count: $audio_device_count"

            for ((index = 0; index < audio_device_count; index++)); do
              device_id=$(jq --argjson index $index '.[$index].name | split(".") | .[1:] | join(".")' <<< "$pactl_data")
              echo "Found audio device with id: $device_id"
              if [[ "$device_id" == "$default_device_id" ]]; then
                findAudioProfiles "$index"
              fi
            done
          '';
        };
      in
      {
        enable = true;
        description = "Initialize default audio device profiles";
        wantedBy = [ "multi-user.target" ];
        after = [ "pipewire.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Environment = "PULSE_SERVER=tcp:localhost:${toString cfg.pulseaudioTcpControlPort}";
          ExecStart = "${initialize-audio-profile}/bin/initialize-audio-profile";
          Restart = "on-failure";
          RestartSec = "1";
        };
      };

    # Open TCP port for the pipewire pulseaudio socket
    networking.firewall.allowedTCPPorts = [
      cfg.pulseaudioTcpPort
      cfg.pulseaudioTcpControlPort
    ];
  };
}
