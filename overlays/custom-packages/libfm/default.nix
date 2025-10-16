# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# This overlay customizes libfm - core library of PCManFM file manager
#
{ prev }:
prev.libfm.overrideAttrs {
  patches = [ ./libfm-folder-reload.patch ];

  env.NIX_CFLAGS_COMPILE = "-Wno-error=incompatible-pointer-types";
}
