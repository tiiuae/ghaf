# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  inherit (lib) mkDefault hasAttr;
  hasStorageVm = (hasAttr "storagevm" config.ghaf) && config.ghaf.storagevm.enable;
in
{
  # Common ghaf user settings
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
