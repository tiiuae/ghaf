# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay is for specific fixes needed only to enable cross-compilation.
#
(_final: prev: {
  libnvidia-container = import ./libnvidia-container { inherit prev; };
  papirus-icon-theme = import ./papirus-icon-theme { inherit prev; };
})
