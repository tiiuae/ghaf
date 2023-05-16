# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{pkgs, ...}:
# account for the development time login with sudo rights
let
  user = "ghaf";
  password = "ghaf";
in {
  users = {
    mutableUsers = true;
    users."${user}" = {
      isNormalUser = true;
      password = password;
      extraGroups = ["wheel" "video" "docker"];
    };
    groups."${user}" = {
      name = "${user}";
      members = ["${user}"];
    };
  };
}
