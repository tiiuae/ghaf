# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Format module for Orin targets — wires ghafImage to sdImage.
#
{ config, ... }:
{
  imports = [ ./sdimage.nix ];
  system.build.ghafImage = config.system.build.sdImage;
}
