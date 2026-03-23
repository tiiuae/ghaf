# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Storage modules - inter-VM communication and persistence
#
# Submodules:
#   channels/           - High-level channel definitions (XDG, identity, desktop shares)
#                         User-facing API that configures how data flows between VMs
#   shared-directories/ - Low-level virtiofs share implementation
#                         Handles the actual host/guest mounts, scanning, notifications
#   persistence.nix     - StorageVM persistent option declaration
#
# Typical usage: Enable channels in global-config, the rest is automatic.
#
{
  _file = ./default.nix;

  imports = [
    ./channels
    ./shared-directories
    ./persistence.nix
  ];
}
