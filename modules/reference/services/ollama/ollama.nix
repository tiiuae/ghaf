# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.reference.services.ollama;
  inherit (lib) mkEnableOption mkIf optionalAttrs;
in
{
  _file = ./ollama.nix;

  options.ghaf.reference.services.ollama = {
    enable = mkEnableOption "Enable the ollama service";
  };

  config = mkIf cfg.enable {
    services.ollama = {
      enable = true;
      openFirewall = true;
      # Use Alpaca's default managed instance port
      # This will force Alpaca to use the system's Ollama instance
      port = 11435;
    };

    # Set the OLLAMA_HOST env var so Ollama is always accessible
    environment.sessionVariables.OLLAMA_HOST = "${config.services.ollama.host}:${toString config.services.ollama.port}";

    systemd.services.ollama = {
      serviceConfig = {
        TimeoutStartSec = "5h";
        Restart = "always";
        RestartSec = "5s";
      };
    };

    ghaf = optionalAttrs (builtins.hasAttr "storagevm" config.ghaf) {
      storagevm.maximumSize = 100 * 1024; # 100 GB space for ollama (models can be large)
      storagevm.directories = [
        {
          directory = "/var/lib/private/ollama";
          mode = "0700";
        }
      ];
    };
  };
}
