<!--
SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: Apache-2.0
-->

# `gui-vm` FSS Root-Cause Runbook

Use this runbook after the FSS policy fix is deployed and the remaining issue is warning-only residual corruption on `gui-vm`.

Goal:

- determine whether new failed files appear during normal idle time
- determine whether new failed files appear only after suspend/resume
- correlate guest-side packets with host-side `gui-vm` lifecycle logs

## Guest Sequence

Run on `gui-vm`:

```bash
sudo fss-rootcause capture-guest --session-dir /var/tmp/gui-rootcause --label pre-idle
sleep 900
sudo fss-rootcause capture-guest --session-dir /var/tmp/gui-rootcause --label post-idle
sudo systemctl suspend
sudo fss-rootcause capture-guest --session-dir /var/tmp/gui-rootcause --label post-suspend
sudo fss-test
```

Then compare the checkpoints:

```bash
sudo fss-rootcause compare --session-dir /var/tmp/gui-rootcause --from pre-idle --to post-idle
sudo fss-rootcause compare --session-dir /var/tmp/gui-rootcause --from post-idle --to post-suspend
```

Important files:

- `/var/tmp/gui-rootcause/guest/<label>/fss-debug/summary/summary.md`
- `/var/tmp/gui-rootcause/compare/pre-idle-vs-post-idle/summary.md`
- `/var/tmp/gui-rootcause/compare/post-idle-vs-post-suspend/summary.md`

## Host Correlation

Run on `ghaf-host` around the same reproduction window:

```bash
sudo fss-rootcause capture-host --session-dir /var/tmp/gui-rootcause --vm-name gui-vm --label post-suspend
```

Important files:

- `/var/tmp/gui-rootcause/host/gui-vm/post-suspend/summary.md`
- `/var/tmp/gui-rootcause/host/gui-vm/post-suspend/05-unit-log.txt`
- `/var/tmp/gui-rootcause/host/gui-vm/post-suspend/08-host-power-events.txt`

## Interpretation

Use these decision rules:

- if `post-idle` already shows new failed files, the corruption is happening during normal session activity
- if `post-idle` is stable but `post-suspend` adds new failed files, the corruption is suspend/resume-correlated
- if host logs show `gui-vm` restart, stop/start, or abnormal unit transitions during the same window, treat that as a VM lifecycle issue first
- if any checkpoint shows `FAIL: .../system.journal`, reclassify the incident as active integrity failure immediately
