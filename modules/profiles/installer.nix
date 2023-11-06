# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.profiles.installer;
in
  with lib; {
    options.ghaf.profiles.installer.enable = mkEnableOption "installer profile";

    config = mkIf cfg.enable {
      # Use less privileged ghaf user
      users.users.ghaf = {
        isNormalUser = true;
        extraGroups = ["wheel" "networkmanager" "video"];
        # Allow the graphical user to login without password
        initialHashedPassword = "";
      };

      # Allow the user to log in as root without a password.
      users.users.root.initialHashedPassword = "";

      # Allow passwordless sudo from ghaf user
      security.sudo = {
        enable = mkDefault true;
        wheelNeedsPassword = mkImageMediaOverride false;
      };

      # Automatically log in at the virtual consoles.
      services.getty.autologinUser = "ghaf";
    };
  }
