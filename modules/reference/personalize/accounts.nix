# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  inherit (lib) mkIf hasAttrByPath;
in
{
  # Account management file for ghaf, allows to declaratively manage user accounts.
  # Password settings are now read from deployment profiles.

  # Only apply account settings on the host, not in VMs
  # VMs inherit user settings from host via microvm/modules.nix managedUserAccounts
  config = mkIf (hasAttrByPath [ "hardware" "devices" ] config.ghaf) {
    ghaf.users = {
      # Default admin account - uses deployment profile settings
      admin = {
        enable = true;
        initialPassword =
          if config.ghaf.reference.deployments.users.adminHashedPassword != null then
            null
          else
            config.ghaf.reference.deployments.users.adminPassword;
        initialHashedPassword = null;
        hashedPassword = config.ghaf.reference.deployments.users.adminHashedPassword;
      };
    };
  };
}
