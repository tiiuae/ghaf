# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:

let
  cfg = config.ghaf.reference.profiles.mvp-user-trial-hardening;
in
{
  imports = [ ./mvp-user-trial.nix ];

  options.ghaf.reference.profiles.mvp-user-trial-hardening = {
    enable = lib.mkEnableOption "the mvp configuration for security features";
  };

  config = lib.mkIf cfg.enable {
    ghaf = {
      reference = {
        profiles = {
          mvp-user-trial.enable = true;
        };
      };

      storage.encryption.enable = true;

      # disable plymouth: not integrated yet with LUKS PIN prompt
      graphics.boot.enable = false;
    };
  };
}
