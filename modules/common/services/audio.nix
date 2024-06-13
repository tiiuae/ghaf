# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.ghaf.services.audio;
  inherit (lib) mkIf mkEnableOption mkOption literalExpression types;
in {
  options.ghaf.services.audio = {
    enable = mkEnableOption "Enable audio service for audio VM";
    pulseaudioTcpPort = mkOption {
      type = types.int;
      default = 4713;
      description = "TCP port used by Pipewire-pulseaudio service";
    };
    appStreams = mkOption {
      description = "Audio streams for ghaf applications";
      type = types.listOf types.str;
      default = [];
      example = literalExpression ''
        [
          "chromium"
          "element"
        ]
      '';
    };
  };

  config = mkIf cfg.enable {
    # Enable pipewire service for audioVM with pulseaudio support
    security.rtkit.enable = true;
    sound.enable = true;
    hardware.firmware = [pkgs.sof-firmware];
    services.pipewire = {
      enable = true;
      pulse.enable = true;
      systemWide = true;

      configPackages = [
        (pkgs.writeTextDir "share/pipewire/pipewire.conf.d/10-remote-simple.conf" ''
          context.modules = [
            {   name = libpipewire-module-protocol-pulse
                args = {
                  server.address = [
                    {
                      # Listen TCP port (4713 by default) for IPv4 and IPv6 on all addresses
                      address = "tcp:0.0.0.0:${toString cfg.pulseaudioTcpPort}"
                      max-clients = 64
                      listen-backlog = 32
                      client.access = "unrestricted"
                    }
                  ];

                  pulse = {
                    min.req          = 128/48000;     # 2.7ms
                    default.req      = 960/48000;     # 20 milliseconds
                    default.tlength  = 4800/48000;     # 100 ms
                    # recording buffer options
                    min.frag         = 128/48000;     # 2.7ms
                    default.frag     = 960/48000;     # 20 ms
                    # Sheduling
                    min.quantum      = 128/48000;     # 2.7ms (test with 1024)
                  }
                }
            }
          ];
        '')
      ];

      extraConfig.pipewire = builtins.listToAttrs (
        map (name:
          lib.attrsets.nameValuePair "91-chennels-${name}-vm"
            {
              "context.objects" = [
                {
                  factory = "adapter";
                  args = {
                    "factory.name"     = "support.null-audio-sink";
                    "node.name"        = "${name}.mic";
                    "node.description" = "${name} Microphone";
                    "media.class"      = "Audio/Source/Virtual";
                    "audio.position"   = "MONO";
                    "target.object"    = "@DEFAULT_SOURCE@";
                  };
                }
                {
                  factory = "adapter";
                  args = {
                    "factory.name"     = "support.null-audio-sink";
                    "node.name"        = "${name}.speaker";
                    "node.description" = "${name} Speaker";
                    "media.class"      = "Audio/Sink";
                    "audio.position"   = "FL,FR";
                    "target.object"    = "@DEFAULT_SINK@";
                  };
                }
              ];
            }
        )
        cfg.appStreams
      );
    };

    hardware.pulseaudio.extraConfig = ''
      # Set sink and source default max volume to about 75% (0-65536)
      set-sink-volume @DEFAULT_SINK@ 48000
      set-source-volume @DEFAULT_SOURCE@ 48000
    '';

    # Allow ghaf user to access pulseaudio and pipewire
    users.extraUsers.ghaf.extraGroups = ["audio" "video" "pulse-access" "pipewire"];

    # Dummy service to get pipewire and pulseaudio services started at boot
    # Normally Pipewire and pulseaudio are started when they are needed by user,
    # We don't have users in audiovm so we need to give PW/PA a slight kick..
    # This calls pulseaudios pa-info binary to get information about pulseaudio current
    # state which starts pipewire-pulseaudio service in the process.
    systemd.services.pulseaudio-starter = {
      after = ["pipewire.service" "network-online.target"];
      requires = ["pipewire.service" "network-online.target"];
      wantedBy = ["default.target"];
      path = [pkgs.coreutils];
      enable = true;
      serviceConfig = {
        User = "ghaf";
        Group = "ghaf";
      };
      script = ''${pkgs.pulseaudio}/bin/pa-info > /dev/null 2>&1'';
    };

    # TODO Automate and fix alsa IO ports
    systemd.services."pipewire-link-starter" = let

      audioLinks = lib.strings.concatLines (
                  lib.lists.forEach cfg.appStreams (name:
                      ''
                      ${pkgs.pipewire}/bin/pw-link --passive $ALSA_PCI_MIC_R ${name}.mic:input_MONO
                      ${pkgs.pipewire}/bin/pw-link --passive ${name}.speaker:monitor_FR $ALSA_PCI_SPK_R
                      ${pkgs.pipewire}/bin/pw-link --passive ${name}.speaker:monitor_FL $ALSA_PCI_SPK_L
                      ''
                  )
                );

      # Read first alsa IO ports from pipewire link output and connect to those
      pipewireLinkStarterScript = pkgs.writeShellScriptBin "pipewire-link-starter" ''
            ALSA_PCI_MIC_R=$(${pkgs.pipewire}/bin/pw-link --output | ${pkgs.gawk}/bin/awk '/alsa_input.pci/ && /capture_FR/{print $1;exit}')
            ALSA_PCI_SPK_R=$(${pkgs.pipewire}/bin/pw-link --input | ${pkgs.gawk}/bin/awk '/alsa_output.pci/ && /playback_FR/{print $1;exit}')
            ALSA_PCI_SPK_L=$(${pkgs.pipewire}/bin/pw-link --input | ${pkgs.gawk}/bin/awk '/alsa_output.pci/ && /playback_FL/{print $1;exit}')

            if [ -z "''${ALSA_PCI_MIC_R}" ] || [ -z "''${ALSA_PCI_SPK_R}" ] || [ -z "''${ALSA_PCI_SPK_L}" ]; then
                echo "No Pipewire-Alsa devices available."
                exit 1
            fi

            ${audioLinks}
            exit 0
        '';
    in {
      enable = true;
      description = "Connect pipewire VM audio links";
      path = [pipewireLinkStarterScript];
      wantedBy = ["default.target"];
      after = ["pipewire.service" "network-online.target" "pulseaudio-starter.service"];
      requires = ["pipewire.service" "network-online.target" "pulseaudio-starter.service"];
      serviceConfig = {
        Type = "simple";
        StandardOutput = "journal";
        StandardError = "journal";
        ExecStart = "${pipewireLinkStarterScript}/bin/pipewire-link-starter";
        Restart = "on-failure";
        RestartSec = "5";
        StartLimitBurst = "5";
      };
    };

    # Open TCP port for the PDF XDG socket
    networking.firewall.allowedTCPPorts = [cfg.pulseaudioTcpPort];
  };
}
