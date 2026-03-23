# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Channel module options definitions
#
{ lib, ... }:
{
  options.ghaf.storage.channels = {
    enable = lib.mkEnableOption "shared directory channels";

    debug = lib.mkEnableOption "debug logging for shared directory channels";

    ghafIdentity = {
      enable = lib.mkEnableOption "host identity data shared to VMs (/persist/shared/identity -> /etc/ghaf-identity)";
      mountPoint = lib.mkOption {
        type = lib.types.path;
        default = "/etc/ghaf-identity";
        description = "Mount point for identity shares.";
        readOnly = true;
      };
    };

    ghafPublicKeys = {
      enable = lib.mkEnableOption "public key publish channel with rw access for admin-vm (wo for others)";
      mountPoint = lib.mkOption {
        type = lib.types.path;
        default = "/etc/ghaf-keys";
        description = "Mount point for ghaf public keys.";
        readOnly = true;
      };
    };

    desktopShares = {
      enable = lib.mkEnableOption "gui-vm <-> app-vm shares, auto-generated using app-vm's desktopShare config.";
      guiMountPoint = lib.mkOption {
        type = lib.types.path;
        default = "/Shares";
        description = "Mount point for desktop shares on GUI-VM side.";
      };
      appvmMountPoint = lib.mkOption {
        type = lib.types.path;
        defaultText = lib.literalExpression ''"/home/''${config.ghaf.users.appUser.name}/Desktop Share"'';
        description = "Mount point for desktop shares on app-vm side. Defaults to user home for file manager visibility.";
      };
    };

    xdg = {
      enable = lib.mkEnableOption "XDG shares (auto-generated from app-vm xdgitems/xdghandlers config)";
      mountPoint = lib.mkOption {
        type = lib.types.path;
        default = "/run/xdg";
        description = "Mount point for XDG shares.";
        readOnly = true;
      };
    };

    extraChannels = lib.mkOption {
      type = lib.types.attrsOf lib.dataChannel;
      default = { };
      description = "Additional custom channel definitions.";
    };
  };
}
