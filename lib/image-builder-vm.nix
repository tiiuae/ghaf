# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs }:
drv:
pkgs.vmTools.runInLinuxVM (
  drv.overrideAttrs (old: {
    memSize = 2048;
    # Large decompressed payloads belong on the host-backed scratch filesystem,
    # not the build VM's tmpfs. Only the disposable /dev/vda is formatted.
    buildCommand = ''
      cd /tmp/xchg
      ${old.buildCommand}
    '';
  })
)
