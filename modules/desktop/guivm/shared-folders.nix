# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# GUI VM Shared Folders Feature Module
#
# This module configures the vinotify guest service for shared folder
# change notifications. This allows the file manager to automatically
# refresh when files change in shared folders.
#
# This module is auto-included when ghaf.storagevm.shared-folders.enable is true.
#
{
  lib,
  pkgs,
  globalConfig,
  ...
}:
let
  # Only enable if shared folders are enabled in globalConfig
  sharedFoldersEnabled = globalConfig.storagevm.shared-folders.enable or false;
in
{
  _file = ./shared-folders.nix;

  config = lib.mkIf sharedFoldersEnabled {
    # Receive shared folder inotify events from the host to automatically refresh the file manager
    systemd.services.vinotify = {
      enable = true;
      description = "vinotify";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "1";
        ExecStart = "${pkgs.vinotify}/bin/vinotify --port 2000 --path /Shares --mode guest";
      };
      startLimitIntervalSec = 0;
    };
  };
}
