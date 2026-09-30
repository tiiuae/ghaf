#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

image=$1 manufacturer=$2 recovery=$3
# Only a fresh build image may be personalized; never discard enrolled keys.
cryptsetup luksDump --dump-json-metadata "$image" |
  jq -e '.keyslots | keys == ["0"]' >/dev/null
cryptsetup reencrypt --batch-mode --force-offline-reencrypt \
  --key-file "$manufacturer" "$image"

# Reencryption can move the surviving keyslot; recovery must occupy slot 1.
slot=$(cryptsetup luksDump --dump-json-metadata "$image" |
  jq -er '.keyslots | keys | if length == 1 then .[0] else error("Expected one keyslot") end')
if [[ $slot != 0 ]]; then
  cryptsetup luksAddKey --batch-mode --key-file "$manufacturer" \
    --new-key-slot 0 "$image" "$manufacturer"
  cryptsetup luksKillSlot --batch-mode --key-file "$manufacturer" "$image" "$slot"
fi
cryptsetup luksAddKey --batch-mode --key-file "$manufacturer" \
  --new-key-slot 1 "$image" "$recovery"
