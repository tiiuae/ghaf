# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ config, lib, ... }:
let
  cfg = config.ghaf.profiles.release;
  inherit (lib) mkEnableOption mkIf;
in
{
  _file = ./release.nix;

  options.ghaf.profiles.release = {
    enable = (mkEnableOption "release profile") // {
      default = false;
    };
  };

  config = mkIf cfg.enable {
    # Enable minimal profile as base
    ghaf.profiles.minimal.enable = true;

    # Enable default accounts and passwords
    # TODO this needs to be refined when we define a policy for the
    # processes and the UID/groups that should be enabled by default
    # if not already covered by systemd
    # ghaf.users.admin.enable = true;
    ghaf = {
      # TODO we should move the nix-setup out of the development namespace
      development = {
        nix-setup.enable = true;
      };

    };
  };
}
