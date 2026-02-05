# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# VM Feature Flags Module (DEPRECATED)
#
# This module is now minimal - VM feature configuration has moved to globalConfig.features.
# The new system supports multi-VM assignment of features:
#
#   ghaf.global-config.features = {
#     fprint.targetVms = [ "gui-vm" "admin-vm" ];  # Run fprint in both VMs
#     wifi.targetVms = [ "net-vm" ];               # Standard net-vm wifi
#     audio.enable = false;                         # Disable audio globally
#   };
#
# See lib/global-config.nix for feature schema and lib.ghaf.features utilities.
#
_: {
  _file = ./modules.nix;

  # No options defined - all VM features moved to globalConfig.features
  # This module kept for backward compatibility (can be removed in future major version)
}
