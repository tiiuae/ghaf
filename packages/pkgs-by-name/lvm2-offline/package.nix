# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  lvm2,
}:

(lvm2.override {
  enableCmdlib = false;
  enableDmeventd = false;
  udevSupport = false;
}).overrideAttrs
  (old: {
    pname = "lvm2-offline";

    patches = (old.patches or [ ]) ++ [ ./offline-regular-files.patch ];

    configureFlags = (old.configureFlags or [ ]) ++ [ "--disable-ioctl" ];

    passthru = (old.passthru or { }) // {
      inherit lvm2;
    };

    meta = (old.meta or { }) // {
      description = "Offline-only LVM2 tools with regular-file PV support";
      longDescription = ''
        LVM2 built without kernel device-mapper ioctl support and patched to
        operate on explicitly configured regular files. This is intended only
        for constructing disk images in sandboxed builds.
      '';
      platforms = lib.platforms.linux;
    };
  })
