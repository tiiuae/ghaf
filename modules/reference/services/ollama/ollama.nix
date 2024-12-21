# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.reference.services;
  inherit (lib) mkIf optionalAttrs;
in
{
  config = mkIf cfg.ollama {
    services.ollama = {
      enable = true;
      openFirewall = true;
      host = "127.0.0.1";
    };

    ghaf = optionalAttrs (builtins.hasAttr "storagevm" config.ghaf) {
      storagevm.directories = [
        {
          directory = "/var/lib/private/ollama";
          mode = "u=rwx,g=,o=";
        }
      ];
    };

    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "load-falcon";
        runtimeInputs = with pkgs; [
          libnotify
          ollama
        ];
        text = ''
          if [ "''${1:-}" == "--check" ]; then
             if ollama show falcon2; then
                echo "falcon2 model is installed"
                exit 0
             fi

             if [ -f /tmp/falcon-download ]; then
               if [ "$(cat /tmp/falcon-download)" == "1" ]; then
                  echo "falcon2 model is currently being installed"
                  exit 0
               fi
             fi

             echo "falcon2 model is not installed"
             exit 1
          fi

          function cleanup() {
             echo 0 > /tmp/falcon-download
          }

          trap cleanup SIGINT

          if ! ollama show falcon2; then
             notify-send -i ${pkgs.ghaf-artwork}/icons/falcon-icon.svg 'Falcon AI' 'Downloading the latest falcon2 model. This may take a while...'
             echo 1 > /tmp/falcon-download
          else
             echo "falcon2 model is already installed"
             exit 0
          fi

          if ollama pull falcon2:latest; then
            notify-send -i ${pkgs.ghaf-artwork}/icons/falcon-icon.svg 'Falcon AI' 'The falcon model has been downloaded successfully. You may now try it out!'
          else
            notify-send -i ${pkgs.ghaf-artwork}/icons/falcon-icon.svg 'Falcon AI' 'Failed to download the falcon model. Please try again later.'
          fi

          cleanup
        '';
      })
    ];

    # This forces Alpaca to use the systemd ollama daemon instead of spawning
    # its own.
    system.userActivationScripts.alpaca-configure = {
      text = ''
        [[ "$UID" != ${toString config.ghaf.users.loginUser.uid} ]] && exit 0
        source ${config.system.build.setEnvironment}
        mkdir -p $HOME/.config/com.jeffser.Alpaca
        cat <<EOF > $HOME/.config/com.jeffser.Alpaca/server.json
        {
          "remote_url": "http://localhost:11434",
          "remote_bearer_token": "",
          "run_remote": true,
          "local_port": 11435,
          "run_on_background": false,
          "powersaver_warning": true,
          "model_tweaks": {
                "temperature": 0.7,
                "seed": 0,
                "keep_alive": 5
          },
          "ollama_overrides": {},
          "idle_timer": 0
        }
        EOF
      '';
    };

    systemd.services.ollama = {
      serviceConfig = {
        TimeoutStartSec = "5h";
        Restart = "always";
        RestartSec = "5s";
      };
    };
  };
}
