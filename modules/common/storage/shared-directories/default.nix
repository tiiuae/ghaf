# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Shared directories - low-level virtiofs implementation
#
# Implements the actual file sharing between host and VMs. Channel definitions
# (from channels/ or custom) specify participants; this module creates the
# virtiofs shares, bind mounts, tmpfiles, and daemon configuration.
#
# Channels have three modes:
#
# 1. fallback: All VMs share the same rw directory (no isolation, not recommended)
#    {channel}/shared/        # virtiofs rw -> all VMs
#
# 2. untrusted: Per-writer isolation with mandatory scanning
#    - Files pass through ClamAV before reaching readers
#    - Requires ghaf.global-config.security.clamav.enable = true
#    - Use for: user data, downloads, external/untrusted inputs
#    {channel}/
#    ├── share/{writer}/    # VM: virtiofs rw, host: bind mount rw
#    ├── export/            # files scanned before aggregation
#    └── export-ro/         # ro bind mount for readers
#
# 3. trusted: Per-writer isolation without scanning
#    - Direct aggregation, no scanning delay
#    - Use for: system config, host-provided resources, trusted data
#    {channel}/
#    ├── share/{writer}/    # VM: virtiofs rw, host: bind mount rw
#    ├── export/            # files passed through directly
#    └── export-ro/         # ro bind mount for readers
#
{ ... }:
{
  _file = ./default.nix;

  imports = [
    ./options.nix
    ./host.nix
    ./vm.nix
  ];
}
