# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  config,
  vmName,
  ...
}: let
  speakerName = "${vmName}.speaker";
  micName = "${vmName}.mic";
in {
#    packages = [
#        pkgs.pulseaudio
#        pkgs.pamixer
#    ];

    # Enable pulseaudio for application VM
    security.rtkit.enable = true;
    sound.enable = true;
    users.extraUsers.ghaf.extraGroups = ["audio" "video"];

    hardware.pulseaudio = {
        enable = true;
        extraConfig = "
            load-module module-tunnel-sink sink=${speakerName} sink_name=${speakerName} server=audio-vm:4713 format=s16le channels=2 rate=48000
            load-module module-tunnel-source source=${micName} source_name=${micName} server=audio-vm:4713 format=s16le channels=1 rate=48000

            # Set sink and source default max volume to about 90% (0-65536)
            set-sink-volume ${speakerName} 60000
            set-source-volume ${micName} 60000
        ";
    };
}
