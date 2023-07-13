# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.ghaf.audio;
in
  with lib; {
    options.ghaf.audio = {
      enable = mkEnableOption "audio";
    };

    config = mkIf cfg.enable {
      sound.enable = true;
      sound.extraConfig = ''
        pcm.dmix_44100{
          type dmix
          ipc_key 5678293
          ipc_key_add_uid yes
          slave{
            pcm "hw:0,0"
            period_time 40000
            format S16_LE
            rate 44100
          }
        }

        pcm.!dsnoop_44100{
          type dsnoop
          ipc_key 5778293
          ipc_key_add_uid yes
          slave{
            pcm "hw:0,0"
            period_time 40000
            format S16_LE
            rate 44100
          }
        }

        pcm.asymed{
          type asym
          playback.pcm "dmix_44100"
          capture.pcm "dsnoop_44100"
        }

        pcm.!default{
          type plug
          route_policy "average"
          slave.pcm "asymed"
        }

        ctl.!default{
          type hw;
          card 0;
        }

        ctl.mixer0{
          type hw
          card 0
        }
      '';
      users.users.ghaf.extraGroups = ["audio"];
    };
  }
