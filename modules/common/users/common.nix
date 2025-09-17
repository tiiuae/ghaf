# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    hasAttr
    mkDefault
    mkOption
    types
    ;
  hasStorageVm = (hasAttr "storagevm" config.ghaf) && config.ghaf.storagevm.enable;
in
{
  options.ghaf.users = {
    profile = mkOption {
      description = "Platform user profile.";
      type = types.enum [
        "homed-user"
        "ad-users"
      ];
      default = "homed-user";
    };
  };

  config = {

    # Disable mutable users
    users.mutableUsers = mkDefault false;

    # Enable userborn
    services.userborn = {
      enable = mkDefault true;
      passwordFilesLocation = if hasStorageVm then "/var/lib/nixos" else "/etc";
    };
  };
}
