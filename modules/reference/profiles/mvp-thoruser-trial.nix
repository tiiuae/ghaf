# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.reference.profiles.mvp-thoruser-trial;
in
{
  _file = ./mvp-thoruser-trial.nix;

  options.ghaf.reference.profiles.mvp-thoruser-trial = {
    enable = lib.mkEnableOption "the mvp configuration for Thor";
  };

  config = lib.mkIf cfg.enable {
    ghaf = {
      profiles.thor.enable = true;

      reference = {
        appvms.enable = false;
        services = {
          enable = false;
          dendrite = false;
        };
        personalize.keys.enable = true;
        desktop.applications.enable = false;
      };

      graphics.boot.enable = lib.mkForce false;
      host.networking.enable = lib.mkForce true;
      security.audit.enable = false;
    };
  };
}
