#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# needs-reflash.sh - decide whether a change can go out with `ghaf-rebuild switch`, or
# needs a full image flash.
#
# `nixos-rebuild switch` replaces the running system generation. It cannot repartition a
# disk, rewrite a bootloader, or change what the firmware loads. When a change touches
# those, switching appears to succeed and leaves the device in a state that does not match
# the image you built — which is worse than an obvious failure, because you then debug the
# wrong system.
#
# Exit status: 0 = rebuild is enough, 1 = reflash needed, 2 = usage error.

set -uo pipefail

BASELINE=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [baseline-ref]

Classify the pending changes as rebuild-safe or reflash-required.

  baseline-ref   What the device is currently running, e.g. the repo_rev from a log
                 snapshot manifest. Defaults to uncommitted changes only.

Exit: 0 rebuild is enough, 1 reflash needed, 2 usage error.
EOF
}

case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
"") BASELINE="" ;;
*) BASELINE="$1" ;;
esac

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Not a git repository." >&2
  exit 2
fi

if [ -n "$BASELINE" ]; then
  if ! git rev-parse --verify --quiet "$BASELINE" >/dev/null; then
    echo "Unknown baseline ref: $BASELINE" >&2
    exit 2
  fi
  CHANGED=$(
    git diff --name-only "$BASELINE"...HEAD
    git diff --name-only HEAD
    git diff --name-only --cached
  )
else
  CHANGED=$(
    git diff --name-only HEAD
    git diff --name-only --cached
  )
fi

CHANGED=$(printf '%s\n' "$CHANGED" | grep -v '^$' | sort -u)

if [ -z "$CHANGED" ]; then
  echo "No changes against ${BASELINE:-the working tree}. Nothing to deploy."
  exit 0
fi

# Each pattern is something `switch` provably cannot apply to a running system.
declare -a REASONS=()
check() {
  local pattern="$1" why="$2" hits
  hits=$(printf '%s\n' "$CHANGED" | grep -E "$pattern" || true)
  if [ -n "$hits" ]; then
    REASONS+=("$why")
    while read -r f; do [ -n "$f" ] && REASONS+=("    $f"); done <<<"$hits"
  fi
}

check '^modules/partitioning/' \
  "Partitioning/disko layout — switch cannot repartition a mounted disk."
check '(^|/)(boot|secureboot)/' \
  "Boot or secure boot — the bootloader and keys are written at image time."
# Hardware definitions live in two places: modules/hardware/ for the shared machinery and
# modules/reference/hardware/ for the per-device definitions (intel-laptop, jetpack, ...).
# Matching only the first misses the file that carries kernelParams for the laptops.
check '^modules/(reference/)?hardware/' \
  "Hardware definition — PCI passthrough IDs and kernel params take effect at boot."
check 'kernel' \
  "Kernel or kernel config — a new kernel needs a boot, and cmdline changes need the bootloader."
check '^modules/microvm/(sysvms|host)/' \
  "MicroVM topology — adding, removing or re-provisioning a VM changes host state that switch does not reconcile."
check '^lib/builders/' \
  "Image builder — how the image itself is assembled."

# Path patterns miss a kernel command line edited inside a file that otherwise looks
# harmless, so look at the content of the change too. The cmdline is baked into the boot
# entry: switching leaves the running kernel with the old parameters.
if [ -n "$BASELINE" ]; then
  DIFF_BODY=$(
    git diff -U0 "$BASELINE"...HEAD -- '*.nix' 2>/dev/null
    git diff -U0 HEAD -- '*.nix' 2>/dev/null
  )
else
  DIFF_BODY=$(
    git diff -U0 HEAD -- '*.nix' 2>/dev/null
    git diff -U0 --cached -- '*.nix' 2>/dev/null
  )
fi
CMDLINE_HITS=$(printf '%s\n' "$DIFF_BODY" |
  grep -E '^[+-][^+-]*(kernelParams|module_blacklist|stage1\.kernelModules|bootloader|disko)' || true)
if [ -n "$CMDLINE_HITS" ]; then
  REASONS+=("Kernel command line or boot/disk configuration edited in place:")
  while read -r l; do [ -n "$l" ] && REASONS+=("    ${l:0:100}"); done <<<"$CMDLINE_HITS"
fi

echo "Changed since ${BASELINE:-working tree}:"
printf '%s\n' "$CHANGED" | sed 's/^/  /'
echo ""

if [ ${#REASONS[@]} -eq 0 ]; then
  cat <<EOF
Verdict: REBUILD is enough.

  ghaf-rebuild <netvm-ip> .#<target> boot
  ssh ghaf@<netvm-ip> -- ssh ghaf-host sudo systemd-run --no-block systemctl reboot

Nothing here changes partitioning, boot, hardware or VM topology.

Prefer 'boot' + reboot over 'switch': the reboot restarts every microVM, so a guest-side
change cannot be left unapplied while the host looks updated -- the most common way to
conclude a fix did not work when it was simply never loaded. It also gives a real boot,
which is the only way to judge start-up ordering and timing. 'switch' remains right when
you deliberately want no downtime, and then you must restart the affected microVMs by hand.
EOF
  exit 0
fi

echo "Verdict: REFLASH required."
echo ""
for r in "${REASONS[@]}"; do echo "  $r"; done
cat <<EOF

A switch would appear to succeed and leave the device not matching the image. Build the
image and flash it instead. If you are certain a particular finding above is inert for your
change, say so explicitly rather than silently switching — the failure mode is a device
that disagrees with your source tree.
EOF
exit 1
