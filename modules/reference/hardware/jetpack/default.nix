# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# ghaf's integration to jetpack-nixos
#
{
  imports = [
    ./profiles
    ./nvidia-jetson-orin
  ];
}
