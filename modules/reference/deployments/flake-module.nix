# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Flake module for deployment profiles
_: {
  flake.nixosModules = {
    reference-deployments.imports = [ ./. ];
  };
}
