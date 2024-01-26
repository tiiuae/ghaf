# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{...}: {
  imports = [
    # Including different users and groups
    ./admin.nix
    ./operator.nix
    ./waypipe.nix
    ./network.nix
    ./groups.nix
  ];
}
