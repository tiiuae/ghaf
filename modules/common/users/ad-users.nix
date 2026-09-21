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
in
{
  _file = ./ad-users.nix;

  options.ghaf.users.adUsers = {
    enable = lib.mkEnableOption "Active Directory user configuration";
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
