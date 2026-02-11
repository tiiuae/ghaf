# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# GUI VM Ghaf Intro Feature Module
#
# This module configures the first-boot Ghaf introduction autostart service.
# It watches for COSMIC initial setup completion and launches the intro app.
#
# This module is auto-included when ghaf-intro is enabled in the reference desktop config.
#
{
  lib,
  pkgs,
  hostConfig,
  ...
}:
let
  # Only enable if ghaf-intro is enabled in the host's reference desktop config
  ghafIntroEnabled = hostConfig.reference.desktop.ghaf-intro.enable or false;

  # Launch ghaf-intro in chrome-vm via givc-cli (it's a Chrome-based app)
  introCommand =
    let
      wrapper = pkgs.writeShellScriptBin "ghaf-intro-autostart" ''
        ${pkgs.givc-cli}/bin/givc-cli ${hostConfig.givc.cliArgs or ""} start app --vm chrome-vm ghaf-intro
      '';
    in
    "${lib.getExe wrapper}";
in
{
  _file = ./ghaf-intro.nix;

  config = lib.mkIf ghafIntroEnabled {
    # First-boot autostart trigger after COSMIC initial setup
    systemd.user.paths.ghaf-intro-autostart = {
      description = "Watch for COSMIC initial setup completion";
      wantedBy = [ "ghaf-session.target" ];
      pathConfig.PathModified = "%h/.config/cosmic-initial-setup-done";
    };

    systemd.user.services.ghaf-intro-autostart = {
      description = "Ghaf Introduction first-boot launcher";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = introCommand;
      };
    };
  };
}
