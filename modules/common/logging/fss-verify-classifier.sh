#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# shellcheck shell=bash
# shellcheck disable=SC2034

# Shared helpers for classifying `journalctl --verify` output.

fss_append_tag() {
  local current="$1"
  local tag="$2"

  if [ -z "$current" ]; then
    printf '%s' "$tag"
  elif printf '%s\n' ",$current," | grep -Fq ",$tag,"; then
    printf '%s' "$current"
  else
    printf '%s,%s' "$current" "$tag"
  fi
}

fss_reason_tags_from_output() {
  local output="$1"
  local tags=""

  if printf '%s\n' "$output" | grep -qi "Bad message"; then
    tags=$(fss_append_tag "$tags" "BAD_MESSAGE")
  fi

  if printf '%s\n' "$output" | grep -qi "Input/output error\|I/O error"; then
    tags=$(fss_append_tag "$tags" "INPUT_OUTPUT_ERROR")
  fi

  if printf '%s\n' "$output" | grep -qi "parse.*seed"; then
    tags=$(fss_append_tag "$tags" "KEY_PARSE_ERROR")
  fi

  if printf '%s\n' "$output" | grep -qi "Required key not available"; then
    tags=$(fss_append_tag "$tags" "KEY_MISSING")
  fi

  if printf '%s\n' "$output" | grep -qi "read-only file system\|permission denied\|cannot create"; then
    tags=$(fss_append_tag "$tags" "FILESYSTEM_RESTRICTION")
  fi

  printf '%s' "$tags"
}

fss_classify_verify_output() {
  local output="$1"
  local real_failures

  # Only actual `FAIL:` records describe failed journal files. Diagnostic
  # context lines such as "Tag failed verification" are useful evidence, but
  # they should not become synthetic failure buckets on their own.
  FSS_FAIL_LINES=$(printf '%s\n' "$output" | grep -E '^FAIL: ' || true)
  FSS_TEMP_FAILURES=$(printf '%s\n' "$FSS_FAIL_LINES" | grep -E '^FAIL: .+\.journal~([[:space:]]|\(|$)' || true)
  real_failures=$(printf '%s\n' "$FSS_FAIL_LINES" | grep -Ev '^FAIL: .+\.journal~([[:space:]]|\(|$)' || true)

  FSS_ACTIVE_SYSTEM_FAILURES=$(printf '%s\n' "$real_failures" | grep -E '^FAIL: .*/system\.journal([[:space:]]|\(|$)' || true)
  FSS_ARCHIVED_SYSTEM_FAILURES=$(printf '%s\n' "$real_failures" | grep -E '^FAIL: .*/system@.*\.journal([[:space:]]|\(|$)' || true)
  FSS_USER_FAILURES=$(printf '%s\n' "$real_failures" | grep -E '^FAIL: .*/user-[0-9]+[^[:space:]]*\.journal([[:space:]]|\(|$)' || true)
  FSS_OTHER_FAILURES=$(printf '%s\n' "$real_failures" | grep -Ev '^FAIL: .*/system\.journal([[:space:]]|\(|$)|^FAIL: .*/system@.*\.journal([[:space:]]|\(|$)|^FAIL: .*/user-[0-9]+[^[:space:]]*\.journal([[:space:]]|\(|$)' || true)

  FSS_KEY_PARSE_ERROR=0
  if printf '%s\n' "$output" | grep -qi "parse.*seed"; then
    FSS_KEY_PARSE_ERROR=1
  fi

  FSS_KEY_REQUIRED_ERROR=0
  if printf '%s\n' "$output" | grep -qi "Required key not available"; then
    FSS_KEY_REQUIRED_ERROR=1
  fi

  FSS_FILESYSTEM_RESTRICTION=0
  if printf '%s\n' "$output" | grep -qi "read-only file system\|permission denied\|cannot create"; then
    FSS_FILESYSTEM_RESTRICTION=1
  fi
}

fss_classification_tags() {
  local tags="$1"

  if [ -n "$FSS_ACTIVE_SYSTEM_FAILURES" ]; then
    tags=$(fss_append_tag "$tags" "ACTIVE_SYSTEM")
  fi

  if [ -n "$FSS_ARCHIVED_SYSTEM_FAILURES" ]; then
    tags=$(fss_append_tag "$tags" "ARCHIVED_SYSTEM")
  fi

  if [ -n "$FSS_USER_FAILURES" ]; then
    tags=$(fss_append_tag "$tags" "USER_JOURNAL")
  fi

  if [ -n "$FSS_TEMP_FAILURES" ]; then
    tags=$(fss_append_tag "$tags" "TEMP")
  fi

  if [ -n "$FSS_OTHER_FAILURES" ]; then
    tags=$(fss_append_tag "$tags" "OTHER_FAILURE")
  fi

  printf '%s' "$tags"
}
