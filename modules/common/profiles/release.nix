# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ config, lib, ... }:
let
  cfg = config.ghaf.profiles.release;
  inherit (lib) mkEnableOption mkIf;
in
{
  options.ghaf.profiles.release = {
    enable = (mkEnableOption "release profile") // {
      default = false;
    };
  };

  config = mkIf cfg.enable {
    # Enable default accounts and passwords
    # TODO this needs to be refined when we define a policy for the
    # processes and the UID/groups that should be enabled by default
    # if not already covered by systemd
    # ghaf.users.admin.enable = true;
  };
}
