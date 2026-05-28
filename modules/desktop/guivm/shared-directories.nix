# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# GUI VM Shared Directories Feature Module
#
# This module configures the vinotify guest service for shared directory
# change notifications. This allows the file manager to automatically
# refresh when files change in shared directories.
#
# This module is auto-included when config.ghaf.storagevm.shared-directories.enable is true.
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Only enable if shared directories are enabled in the VM's own config
  # (set by guivm-base.nix: ghaf.storagevm.shared-directories.enable = true)
  sharedFoldersEnabled = config.ghaf.storagevm.shared-directories.enable or false;
in
{
  _file = ./shared-directories.nix;

  config = lib.mkIf sharedFoldersEnabled {
    # Receive shared directory inotify events from the host to automatically refresh the file manager
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
