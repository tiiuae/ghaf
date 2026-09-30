# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Capability enable for Active Directory login. The domain configuration
# itself lives in ghaf.users.active-directory.domains, populated by the org
# layer (ghaf.org.identity.activeDirectory.domains) or set directly.
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.users.adUsers;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    ;
in
{
  _file = ./ad-users.nix;

  options.ghaf.users.adUsers = {
    enable = mkEnableOption "Active Directory user configuration";

    override = {
      enable = mkOption {
        description = "Enable override for Active Directory user configuration.";
        type = types.bool;
        default = true;
      };
      uid = mkOption {
        description = "UID override for Active Directory user.";
        type = types.int;
        default = 1000;
      };
      gid = mkOption {
        description = "GID override for Active Directory user.";
        type = types.int;
        default = 100;
      };
      loginShell = mkOption {
        description = "Login shell for the user.";
        type = types.str;
        default = "/run/current-system/sw/bin/bash";
      };
    };
  };

  config = {

    assertions = [
      {
        assertion = !cfg.enable || config.ghaf.users.active-directory.domains != { };
        message =
          "ghaf.users.adUsers.enable needs an AD domain. "
          + "Set ghaf.org.identity.activeDirectory.domains (or ghaf.users.active-directory.domains).";
      }
    ];

    # Enable SSSD for Active Directory integration
    ghaf.services.sssd = {
      inherit (cfg) enable;
      debugLevel = 6;
      inherit (config.ghaf.users.active-directory) domains;
    };

  };
}
