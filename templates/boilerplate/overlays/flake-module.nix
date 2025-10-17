# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Flake module for exporting overlays
{
  flake.overlays = {
    cross-compilation = import ./cross-compilation;
    custom-packages = import ./custom-packages;
  };
}
