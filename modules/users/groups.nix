# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  config,
  ...
}: {
  users.groups.admin = {
    name = "admin";
    members = ["admin"];
  };
  # Add root user only for debug builds
  users.users.admin.extraGroups = lib.mkIf config.ghaf.profiles.debug.enable ["wheel"];
}
