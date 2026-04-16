# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ prev }:
prev.blueman.overrideAttrs {
  patches = [ ./0001-blueman-applet-switch-register-agent-sync-call.patch ];
}
