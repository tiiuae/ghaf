# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Format module for Orin targets — wires ghafImage to ghafFlashImages.
#
{ config, ... }:
{
  system.build.ghafImage = config.system.build.ghafFlashImages;
}
