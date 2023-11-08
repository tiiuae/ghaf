# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
(final: prev: {
  dbus-over-ssh = final.callPackage ../../../user-apps/dbus-over-ssh {};
})
