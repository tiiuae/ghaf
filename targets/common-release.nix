# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Common modules for all release-targets
{
  imports = [
    ./common.nix
  ];

  ghaf.host.minification = {
    reduceProfile = true;
    disableNetwork = true;
    disableGetty = true;
    disableGuestVms = true;
  };
}
