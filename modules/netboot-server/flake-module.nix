# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Not part of any Ghaf profile: this configures the machine that SERVES installs,
# not a machine running Ghaf. Import it explicitly on a provisioning server.
{
  flake.nixosModules.netboot-server = ./netboot-server.nix;
}
