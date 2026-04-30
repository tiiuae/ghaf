# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# shellcheck shell=bash

# Shared helpers for classifying `journalctl --verify` output and deciding
# the verification policy verdict. Sourced by the FSS setup service, the
# verify service, the fss-test operator script, and the NixOS VM tests.

# ANSI colors (enabled only when stdout is a terminal).
if [ -t 1 ]; then
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[1;33m'
  NC=$'\033[0m'
else
  RED=""
  GREEN=""
  YELLOW=""
  NC=""
fi

fss_log() {
  local level="${1:-info}"
  local msg="${2-}"
  local color="" label

  shopt -s nocasematch
  case "$level" in
  pass)
    label=PASS
    color="$GREEN"
    ;;
  fail | failure | error)
    label=FAIL
    color="$RED"
    ;;
  warn | warning)
    label=WARN
    color="$YELLOW"
    ;;
  info | *)
    label=INFO
    color=""
    ;;
  esac
  shopt -u nocasematch

  if [ -n "$color" ]; then
    printf '%b[%s]%b %s\n' "$color" "$label" "$NC" "$msg"
  else
    printf '[%s] %s\n' "$label" "$msg"
  fi
}

fss_log_block() { cat; }

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

fss_append_line() {
  local current="$1"
  local line="$2"

  if [ -z "$current" ]; then
    printf '%s' "$line"
  else
    printf '%s\n%s' "$current" "$line"
  fi
}

fss_append_unique_line() {
  local current="$1"
  local line="$2"

  if [ -z "$line" ]; then
    printf '%s' "$current"
  elif printf '%s\n' "$current" | grep -Fxq "$line"; then
    printf '%s' "$current"
  else
    fss_append_line "$current" "$line"
  fi
}

fss_count_nonempty_lines() {
  local text="$1"
  local line
  local count=0

  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] && count=$((count + 1))
  done <<<"$text"

  printf '%s' "$count"
}

fss_failure_bucket_for_path() {
  case "$1" in
  *.journal~) printf '%s' "temp" ;;
  */system.journal) printf '%s' "active-system" ;;
  */system@*.journal) printf '%s' "archived-system" ;;
  */user-[0-9]*.journal) printf '%s' "user-journal" ;;
  *) printf '%s' "other" ;;
  esac
}

fss_unique_fail_paths_from_output() {
  local output="$1"
  local line failure_path unique=""

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
    FAIL:\ *)
      failure_path="${line#FAIL: }"
      failure_path="${failure_path%% *}"
      if [ -n "$failure_path" ] && ! printf '%s\n' "$unique" | grep -Fxq "$failure_path"; then
        unique=$(fss_append_line "$unique" "$failure_path")
      fi
      ;;
    esac
  done <<<"$output"

  printf '%s' "$unique"
}

fss_path_list_contains() {
  local path_list="$1"
  local needle="$2"
  [ -n "$needle" ] && printf '%s\n' "$path_list" | grep -Fxq "$needle"
}

fss_merge_path_lists() {
  local merged="$1"
  local additions="$2"
  local line

  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    merged=$(fss_append_unique_line "$merged" "$line")
  done <<<"$additions"

  printf '%s' "$merged"
}

fss_read_recorded_pre_fss_archive() {
  local state_file="$1"
  [ -r "$state_file" ] && [ -s "$state_file" ] && tr -d '[:space:]' <"$state_file"
}

fss_read_recorded_archive_list() {
  local state_file="$1"
  local line archive_paths=""

  if [ -r "$state_file" ] && [ -s "$state_file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line=$(printf '%s' "$line" | tr -d '[:space:]')
      [ -n "$line" ] || continue
      archive_paths=$(fss_append_unique_line "$archive_paths" "$line")
    done <"$state_file"
  fi

  printf '%s' "$archive_paths"
}

fss_matches_only_expected_archived_system_failure() {
  local expected_archive="$1"
  local archived_failures="${2:-$FSS_ARCHIVED_SYSTEM_FAILURES}"
  local archive_fail_paths

  [ -z "$expected_archive" ] || [ -z "$archived_failures" ] && return 1
  archive_fail_paths=$(fss_unique_fail_paths_from_output "$archived_failures")
  [ "$(fss_count_nonempty_lines "$archive_fail_paths")" -eq 1 ] || return 1
  [ "$archive_fail_paths" = "$expected_archive" ]
}

fss_archived_system_failures_match_allowlist() {
  local allowed_archives="$1"
  local archived_failures="${2:-$FSS_ARCHIVED_SYSTEM_FAILURES}"
  local archive_fail_paths archive_path

  [ -z "$allowed_archives" ] || [ -z "$archived_failures" ] && return 1
  archive_fail_paths=$(fss_unique_fail_paths_from_output "$archived_failures")
  [ -n "$archive_fail_paths" ] || return 1

  while IFS= read -r archive_path || [ -n "$archive_path" ]; do
    [ -n "$archive_path" ] || continue
    fss_path_list_contains "$allowed_archives" "$archive_path" || return 1
  done <<<"$archive_fail_paths"
}

fss_reset_classification() {
  # The FSS_* state variables below are consumed by callers that source
  # this library. shellcheck cannot see those references.
  # shellcheck disable=SC2034
  FSS_REASON_TAGS=""
  FSS_FAIL_LINES=""
  FSS_TEMP_FAILURES=""
  FSS_ACTIVE_SYSTEM_FAILURES=""
  FSS_ARCHIVED_SYSTEM_FAILURES=""
  FSS_USER_FAILURES=""
  FSS_OTHER_FAILURES=""
  FSS_KEY_PARSE_ERROR=0
  FSS_KEY_REQUIRED_ERROR=0
  FSS_FILESYSTEM_RESTRICTION=0
  FSS_VERDICT=""
  FSS_VERDICT_REASON=""
  FSS_VERDICT_TAGS=""
}

fss_reason_tags_from_output() {
  fss_classify_verify_output "$1"
  printf '%s' "$FSS_REASON_TAGS"
}

fss_classify_verify_output() {
  local output="$1"
  local line line_lower failure_path bucket

  fss_reset_classification

  while IFS= read -r line || [ -n "$line" ]; do
    line_lower="${line,,}"

    case "$line_lower" in
    *"bad message"*)
      FSS_REASON_TAGS=$(fss_append_tag "$FSS_REASON_TAGS" "BAD_MESSAGE")
      ;;&
    *"input/output error"* | *"i/o error"*)
      FSS_REASON_TAGS=$(fss_append_tag "$FSS_REASON_TAGS" "INPUT_OUTPUT_ERROR")
      ;;&
    *parse*seed*)
      FSS_REASON_TAGS=$(fss_append_tag "$FSS_REASON_TAGS" "KEY_PARSE_ERROR")
      FSS_KEY_PARSE_ERROR=1
      ;;&
    *"required key not available"*)
      FSS_REASON_TAGS=$(fss_append_tag "$FSS_REASON_TAGS" "KEY_MISSING")
      FSS_KEY_REQUIRED_ERROR=1
      ;;&
    *"read-only file system"* | *"permission denied"* | *"cannot create"*)
      FSS_REASON_TAGS=$(fss_append_tag "$FSS_REASON_TAGS" "FILESYSTEM_RESTRICTION")
      FSS_FILESYSTEM_RESTRICTION=1
      ;;&
    *) ;;
    esac

    case "$line" in
    FAIL:\ *)
      FSS_FAIL_LINES=$(fss_append_line "$FSS_FAIL_LINES" "$line")
      failure_path="${line#FAIL: }"
      failure_path="${failure_path%% *}"
      bucket=$(fss_failure_bucket_for_path "$failure_path")
      case "$bucket" in
      temp) FSS_TEMP_FAILURES=$(fss_append_line "$FSS_TEMP_FAILURES" "$line") ;;
      active-system) FSS_ACTIVE_SYSTEM_FAILURES=$(fss_append_line "$FSS_ACTIVE_SYSTEM_FAILURES" "$line") ;;
      archived-system) FSS_ARCHIVED_SYSTEM_FAILURES=$(fss_append_line "$FSS_ARCHIVED_SYSTEM_FAILURES" "$line") ;;
      user-journal) FSS_USER_FAILURES=$(fss_append_line "$FSS_USER_FAILURES" "$line") ;;
      *) FSS_OTHER_FAILURES=$(fss_append_line "$FSS_OTHER_FAILURES" "$line") ;;
      esac
      ;;
    esac
  done <<<"$output"
}

fss_classification_tags() {
  local tags="${1:-$FSS_REASON_TAGS}"
  local vars=(FSS_ACTIVE_SYSTEM_FAILURES FSS_ARCHIVED_SYSTEM_FAILURES FSS_USER_FAILURES FSS_TEMP_FAILURES FSS_OTHER_FAILURES)
  local labels=(ACTIVE_SYSTEM ARCHIVED_SYSTEM USER_JOURNAL TEMP OTHER_FAILURE)
  local i

  for i in "${!vars[@]}"; do
    [ -n "${!vars[$i]}" ] && tags=$(fss_append_tag "$tags" "${labels[$i]}")
  done

  printf '%s' "$tags"
}

# Decide the verification policy verdict based on populated FSS_* state vars.
# Inputs:
#   $1 = expected pre-FSS archive path (single line, optional)
#   $2 = expected recovery archive paths (newline-separated, optional)
# Outputs (as globals):
#   FSS_VERDICT        = pass | partial | fail
#   FSS_VERDICT_REASON = short human-readable reason
#   FSS_VERDICT_TAGS   = classification tags augmented with PRE_FSS_ARCHIVE / RECOVERY_ARCHIVE
# Requires fss_classify_verify_output to have been called first.
fss_verify_policy_decision() {
  local expected_pre="${1-}"
  local expected_recovery="${2-}"
  local allowed_list="" archived_paths path

  FSS_VERDICT_TAGS=$(fss_classification_tags)
  FSS_VERDICT_REASON=""

  if [ -n "$expected_pre" ]; then
    allowed_list=$(fss_append_unique_line "$allowed_list" "$expected_pre")
  fi
  allowed_list=$(fss_merge_path_lists "$allowed_list" "$expected_recovery")

  if [ "$FSS_KEY_PARSE_ERROR" = 1 ] || [ "$FSS_KEY_REQUIRED_ERROR" = 1 ]; then
    FSS_VERDICT=fail
    FSS_VERDICT_REASON="verification key defect"
    return 0
  fi

  if [ -n "$FSS_ACTIVE_SYSTEM_FAILURES" ]; then
    FSS_VERDICT=fail
    FSS_VERDICT_REASON="active system journal verification failed"
    return 0
  fi

  if [ -n "$FSS_OTHER_FAILURES" ]; then
    FSS_VERDICT=fail
    FSS_VERDICT_REASON="unclassified critical failures"
    return 0
  fi

  local archived_allowed=0
  if [ -n "$FSS_ARCHIVED_SYSTEM_FAILURES" ]; then
    if fss_archived_system_failures_match_allowlist "$allowed_list"; then
      archived_allowed=1
      archived_paths=$(fss_unique_fail_paths_from_output "$FSS_ARCHIVED_SYSTEM_FAILURES")
      while IFS= read -r path || [ -n "$path" ]; do
        [ -n "$path" ] || continue
        if [ "$path" = "$expected_pre" ]; then
          FSS_VERDICT_TAGS=$(fss_append_tag "$FSS_VERDICT_TAGS" "PRE_FSS_ARCHIVE")
        fi
        if fss_path_list_contains "$expected_recovery" "$path"; then
          FSS_VERDICT_TAGS=$(fss_append_tag "$FSS_VERDICT_TAGS" "RECOVERY_ARCHIVE")
        fi
      done <<<"$archived_paths"
    else
      FSS_VERDICT=fail
      FSS_VERDICT_REASON="archived system journal failures outside allowlist"
      return 0
    fi
  fi

  if [ "$archived_allowed" = 1 ] || [ -n "$FSS_USER_FAILURES" ]; then
    FSS_VERDICT=partial
    FSS_VERDICT_REASON="recorded archived-system and/or user exceptions only"
    return 0
  fi

  if [ "$FSS_FILESYSTEM_RESTRICTION" = 1 ]; then
    FSS_VERDICT=partial
    FSS_VERDICT_REASON="filesystem restrictions encountered"
    return 0
  fi

  if [ -n "$FSS_TEMP_FAILURES" ]; then
    FSS_VERDICT=pass
    FSS_VERDICT_REASON="temporary journal files ignored"
    return 0
  fi

  # shellcheck disable=SC2034  # read by consumers that source this library
  FSS_VERDICT=pass
  # shellcheck disable=SC2034
  FSS_VERDICT_REASON=""
}
