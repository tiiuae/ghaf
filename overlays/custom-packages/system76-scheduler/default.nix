# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ prev }:

prev.system76-scheduler.overrideAttrs (_old: {
  patches = [ ./0001-fix-add-missing-loop-in-process-scheduler-refresh-ta.patch ];
})
