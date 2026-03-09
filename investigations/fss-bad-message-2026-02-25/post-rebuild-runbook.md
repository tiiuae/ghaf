<!--
SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: Apache-2.0
-->

# Post-Rebuild FSS Runbook

Use this packet after the rebuilt host has booted and is reachable.

## Automated Pass

From the repo root, run:

```bash
./investigations/fss-bad-message-2026-02-25/post-rebuild-collect.sh
```

Defaults:
- host baseline on `root@ghaf-host`
- `net-vm` baseline via `ProxyJump root@ghaf-host`
- `net-vm` commands run under `sudo` when the SSH target is non-root
- 1 hour soak
- output to `investigations/fss-bad-message-2026-02-25/raw-logs/post-rebuild-<UTC timestamp>/`

Useful options:

```bash
./investigations/fss-bad-message-2026-02-25/post-rebuild-collect.sh --skip-net-vm
./investigations/fss-bad-message-2026-02-25/post-rebuild-collect.sh --skip-soak
./investigations/fss-bad-message-2026-02-25/post-rebuild-collect.sh --soak-minutes 15
```

Read these outputs first:
- `summary/baseline-summary.md`
- `host/07-verify-full.txt`
- `host/08-verify-system-journal.txt`
- `host/06-journald-log.txt`
- `net-vm/07-verify-full.txt` when collected

## Classification Rules

Interpret `journalctl --verify` output with the same buckets as the service and `fss-test`:

- `ACTIVE_SYSTEM`: any `FAIL:` on `system.journal`; critical
- `ARCHIVED_SYSTEM`: only `system@...journal` fails while active system journal passes; warning
- `USER_JOURNAL`: only `user-*.journal` fails while active system journal passes; warning
- `TEMP`: only `*.journal~`; ignore for pass/fail
- `KEY_DEFECT`: `Required key not available`, seed parse failure, missing or unreadable key; config defect

Acceptance after rebuild:
- host `ACTIVE_SYSTEM` must be absent
- `net-vm` `ACTIVE_SYSTEM` should be absent if the access path is available
- no new `systemd-journald` recovery line should coincide with a new FSS failure
- the 1 hour soak should show no repeat host service failures

## Manual Follow-Up Trigger

Collect `admin-vm` and `business-vm` manually if any of these is true:
- host classification is not `clean` or `temp_only`
- `net-vm` classification is not `clean` or `temp_only`
- `journal-fss-verify.service` fails even though raw verify output looks clean
- `fss-test` fails while raw verify output looks clean
- the access path to `net-vm` is degraded after the rebuild

The collector writes the trigger reason to:

```text
.../summary/manual-vm-followup.md
```

## Manual VM Packet

Run the block below inside `admin-vm` and `business-vm` when triggered. Save the full output with a UTC timestamp.

```bash
date -u
hostname
id -un
systemctl status --no-pager journal-fss-setup.service || true
systemctl show journal-fss-verify.service -p ActiveState,SubState,Result,ExecMainStatus,ExecMainCode --no-pager || true
journalctl -u journal-fss-verify.service --no-pager -b -n 300 || true
journalctl -u systemd-journald --no-pager -b -n 400 | grep -Ei "corrupt|unclean|renam|I/O|Bad message|journal" || true
journalctl --list-boots --no-pager || true

MID=$(cat /etc/machine-id)
FSS_CONFIG="/var/log/journal/$MID/fss-config"
KEY_DIR=""
if [ -s "$FSS_CONFIG" ]; then
  KEY_DIR=$(cat "$FSS_CONFIG")
else
  HOSTNAME=$(hostname)
  for CANDIDATE in "/persist/common/journal-fss/$HOSTNAME" "/etc/common/journal-fss/$HOSTNAME"; do
    if [ -d "$CANDIDATE" ]; then
      KEY_DIR="$CANDIDATE"
      break
    fi
  done
fi

echo "machine_id=$MID"
echo "key_dir=$KEY_DIR"
ls -l /var/log/journal/$MID/fss* /run/log/journal/$MID/fss* 2>/dev/null || true
if [ -n "$KEY_DIR" ]; then
  ls -l "$KEY_DIR" 2>/dev/null || true
fi

if [ -n "$KEY_DIR" ] && [ -r "$KEY_DIR/verification-key" ] && [ -s "$KEY_DIR/verification-key" ]; then
  KEY=$(cat "$KEY_DIR/verification-key")
  journalctl --verify --verify-key="$KEY" || true

  if [ -f "/var/log/journal/$MID/system.journal" ]; then
    journalctl --verify --verify-key="$KEY" --file="/var/log/journal/$MID/system.journal" || true
  elif [ -f "/run/log/journal/$MID/system.journal" ]; then
    journalctl --verify --verify-key="$KEY" --file="/run/log/journal/$MID/system.journal" || true
  fi
else
  echo "ERROR: Required key not available"
fi

if command -v fss-test >/dev/null 2>&1; then
  fss-test || true
fi
```
