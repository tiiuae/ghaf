# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkDefault
    ;
  cfg = config.ghaf.users.profile;
  hasStorageVm = (lib.hasAttr "storagevm" config.ghaf) && config.ghaf.storagevm.enable;
in
{
  options.ghaf.users.profile = {
    ad-users = {
      enable = mkEnableOption "Active Directory users for UI login";
    };
    homed-user = {
      enable = mkEnableOption "User profile with homed users";
    };
  };

  config = {

    assertions = [
      {
        assertion = cfg.ad-users.enable -> !cfg.homed-user.enable;
        message = "You cannot enable both systemd-homed and active directory user profiles at the same time.";
      }
    ];

    # Disable mutable users
    users.mutableUsers = mkDefault false;

    # Enable userborn
    services.userborn = {
      enable = mkDefault true;
      passwordFilesLocation = if hasStorageVm then "/var/lib/nixos" else "/etc";
    };
  };
}
