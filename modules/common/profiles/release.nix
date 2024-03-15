# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  lib,
  ...
}: let
  cfg = config.ghaf.profiles.release;
in
  with lib; {
    options.ghaf.profiles.release = {
      enable = mkEnableOption "release profile";
    };

    config = mkIf cfg.enable {
      # Enable default accounts and passwords
      # TODO this needs to be refined when we define a policy for the
      # processes and the UID/groups that should be enabled by default
      # if not already covered by systemd
      ghaf.users.ghaf.account.enable = true;
      ghaf.users.operator.account.enable = true;
      ghaf.users.update.account.enable = true;

      users.mutableUsers = false;
      # TODO Need to comment root.hashedPassword even in release
      # until we have another remote update mechanism in place
      # users.users.root.hashedPassword = "!";
    };
  }
