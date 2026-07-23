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
  */system.journal | */system.journal~) printf '%s' "active-system" ;;
  */system@*.journal | */system@*.journal~) printf '%s' "archived-system" ;;
  */user-[0-9]*.journal | */user-[0-9]*.journal~) printf '%s' "user-journal" ;;
  *.journal~) printf '%s' "temp" ;;
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

# Lifecycle receipts.
#
# Each receipt is a TSV record describing one archived journal that was rotated
# by a known lifecycle event, so the verifier can recognise expected exceptions
# by content-bound identity rather than by path string alone. Schema (v1):
#   schema_version  path  inode  size  boot_id  mtime  sha256  reason  event_id
# shellcheck disable=SC2034  # read by the setup script that sources this library
FSS_RECEIPT_SCHEMA_VERSION="v1"

fss_valid_sha256() {
  printf '%s' "$1" | grep -Eq '^[0-9a-f]{64}$'
}

# Read receipt records from a state file, dropping blank lines.
fss_read_receipts() {
  local state_file="$1"
  [ -r "$state_file" ] && [ -s "$state_file" ] || return 0
  grep -v '^[[:space:]]*$' "$state_file" || true
}

# Emit the deduplicated archive paths referenced by a set of receipt records.
fss_receipt_paths() {
  local records="$1"
  local rec ver path rest paths=""

  while IFS= read -r rec || [ -n "$rec" ]; do
    [ -n "$rec" ] || continue
    # shellcheck disable=SC2034  # ver/rest are positional placeholders
    IFS=$'\t' read -r ver path rest <<<"$rec"
    [ -n "$path" ] || continue
    paths=$(fss_append_unique_line "$paths" "$path")
  done <<<"$records"

  printf '%s' "$paths"
}

# Print the boot_id recorded for a path; return non-zero when no receipt matches.
fss_receipt_boot_for_path() {
  local records="$1"
  local needle="$2"
  local rec ver path inode size boot rest

  [ -n "$needle" ] || return 1
  while IFS= read -r rec || [ -n "$rec" ]; do
    [ -n "$rec" ] || continue
    # shellcheck disable=SC2034  # ver/inode/size/rest are positional placeholders
    IFS=$'\t' read -r ver path inode size boot rest <<<"$rec"
    if [ "$path" = "$needle" ]; then
      printf '%s' "$boot"
      return 0
    fi
  done <<<"$records"

  return 1
}

# Return success if any receipt was recorded for the specified boot id.
fss_receipts_contain_boot() {
  local records="$1"
  local needle_boot="$2"
  local rec ver path inode size boot rest

  [ -n "$needle_boot" ] || return 1
  while IFS= read -r rec || [ -n "$rec" ]; do
    [ -n "$rec" ] || continue
    # shellcheck disable=SC2034  # ver/path/inode/size/rest are positional placeholders
    IFS=$'\t' read -r ver path inode size boot rest <<<"$rec"
    if [ "$boot" = "$needle_boot" ]; then
      return 0
    fi
  done <<<"$records"

  return 1
}

# Return success if any receipt was recorded for a boot id other than the current one.
fss_receipts_contain_other_boot() {
  local records="$1"
  local current_boot="$2"
  local rec ver path inode size boot rest

  [ -n "$current_boot" ] || return 1
  while IFS= read -r rec || [ -n "$rec" ]; do
    [ -n "$rec" ] || continue
    # shellcheck disable=SC2034  # ver/path/inode/size/rest are positional placeholders
    IFS=$'\t' read -r ver path inode size boot rest <<<"$rec"
    if [ -n "$boot" ] && [ "$boot" != "$current_boot" ]; then
      return 0
    fi
  done <<<"$records"

  return 1
}

# Filter receipt records against the live filesystem, emitting only those whose
# recorded content still matches the on-disk archive. Matching is by sha256
# content identity (the durable evidence artifact), so it is stable across inode
# changes (e.g. cross-filesystem moves) but rejects a substituted archive
# (path reuse) or a vanished one. A missing/malformed sha is non-exculpatory:
# the record is dropped rather than falling back to weaker size-only matching.
# Requires real files; the pure policy decision does not call this so it stays
# unit-testable on synthetic records.
fss_filter_valid_receipts() {
  local records="$1"
  local rec ver path inode size boot mtime sha rest
  local cur_sha

  while IFS= read -r rec || [ -n "$rec" ]; do
    [ -n "$rec" ] || continue
    # shellcheck disable=SC2034  # ver/inode/size/boot/mtime/rest are positional placeholders
    IFS=$'\t' read -r ver path inode size boot mtime sha rest <<<"$rec"
    [ -n "$path" ] && [ -f "$path" ] || continue
    fss_valid_sha256 "$sha" || continue
    cur_sha=$(sha256sum "$path" 2>/dev/null | cut -d' ' -f1 || true)
    [ "$cur_sha" = "$sha" ] || continue

    printf '%s\n' "$rec"
  done <<<"$records"
}

# Emit paths whose receipt still points at an on-disk archive but whose content no
# longer matches the recorded receipt. Missing files are ignored here because
# journald retention can legitimately delete archives; an existing mismatched file
# is treated as substitution/path reuse and must fail closed.
fss_receipt_mismatches() {
  local records="$1"
  local rec ver path inode size boot mtime sha rest
  local cur_sha mismatches=""

  while IFS= read -r rec || [ -n "$rec" ]; do
    [ -n "$rec" ] || continue
    # shellcheck disable=SC2034  # ver/inode/size/boot/mtime/rest are positional placeholders
    IFS=$'\t' read -r ver path inode size boot mtime sha rest <<<"$rec"
    [ -n "$path" ] && [ -f "$path" ] || continue
    fss_valid_sha256 "$sha" || continue
    cur_sha=$(sha256sum "$path" 2>/dev/null | cut -d' ' -f1 || true)
    [ "$cur_sha" = "$sha" ] && continue

    mismatches=$(fss_append_unique_line "$mismatches" "$path")
  done <<<"$records"

  printf '%s' "$mismatches"
}

fss_read_pre_activation_receipts() {
  fss_read_receipts "$1"
}

fss_pre_activation_receipt_paths() {
  fss_receipt_paths "$1"
}

fss_pre_activation_boot_for_path() {
  fss_receipt_boot_for_path "$1" "$2"
}

fss_pre_activation_receipts_contain_boot() {
  fss_receipts_contain_boot "$1" "$2"
}

fss_pre_activation_receipts_contain_other_boot() {
  fss_receipts_contain_other_boot "$1" "$2"
}

fss_pre_activation_receipt_mismatches() {
  fss_receipt_mismatches "$1"
}

# Unclean-shutdown receipts: journals journald itself reported as "corrupted or
# uncleanly shut down" and renamed to <path>~ (host crash, power loss, stop-timeout
# SIGKILL). Same v1 receipt schema and content-binding as the other classes.
fss_read_unclean_shutdown_receipts() {
  fss_read_receipts "$1"
}

fss_unclean_shutdown_receipt_paths() {
  fss_receipt_paths "$1"
}

fss_unclean_shutdown_boot_for_path() {
  fss_receipt_boot_for_path "$1" "$2"
}

fss_unclean_shutdown_receipts_contain_boot() {
  fss_receipts_contain_boot "$1" "$2"
}

fss_unclean_shutdown_receipts_contain_other_boot() {
  fss_receipts_contain_other_boot "$1" "$2"
}

fss_unclean_shutdown_receipt_mismatches() {
  fss_receipt_mismatches "$1"
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
  # shellcheck disable=SC2034  # read by consumers that source this library
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
#   $2 = expected recovery receipt records (TSV, newline-separated, optional)
#   $3 = pre-activation receipt records (TSV, newline-separated, optional)
#   $4 = current boot_id (optional; distinguishes this boot's boundary from stale)
#   $5 = journalctl --verify exit code (optional; nonzero unclassified exits fail)
# Outputs (as globals):
#   FSS_VERDICT        = verified | verified-with-exception | warning | fail
#   FSS_VERDICT_REASON = short human-readable reason
#   FSS_VERDICT_TAGS   = classification tags augmented with PRE_FSS_ARCHIVE /
#                        RECOVERY_ARCHIVE / PRE_ACTIVATION_ARCHIVE / PRE_ACTIVATION_STALE
# Verdict semantics (per .idea/ Layer-5 policy states):
#   verified                 - all journals verify, no exceptions.
#   verified-with-exception  - only evidence-backed exceptions for THIS boot
#                              (pre-FSS / recovery / current-boot insecure boot logs).
#   warning                  - exceptions evidenced but from an earlier boot, or
#                              user/temp/filesystem-only issues.
#   fail                     - active-system failure, key defect, unclassified
#                              failure, or an archived failure with no matching
#                              receipt (unrecorded or content-substituted).
# Receipt matching is content-bound: callers should pass receipts already filtered
# against disk (see fss_filter_valid_receipts) so a substituted archive presents
# as unmatched and fails closed. Requires fss_classify_verify_output first.
fss_verify_policy_decision() {
  local expected_pre="${1-}"
  local recovery_receipts="${2-}"
  local pre_activation_receipts="${3-}"
  local current_boot="${4-}"
  local verify_exit="${5:-0}"
  local unclean_shutdown_receipts="${6-}"
  local allowed_list="" recovery_paths pre_activation_paths unclean_paths archived_paths path boot
  local recovery_seen=0 recovery_stale=0
  local pre_activation_seen=0 pre_activation_stale=0 exception_seen=0
  local unclean_seen=0 unclean_stale=0

  FSS_VERDICT_TAGS=$(fss_classification_tags)
  FSS_VERDICT_REASON=""

  recovery_paths=$(fss_receipt_paths "$recovery_receipts")
  pre_activation_paths=$(fss_pre_activation_receipt_paths "$pre_activation_receipts")
  unclean_paths=$(fss_unclean_shutdown_receipt_paths "$unclean_shutdown_receipts")
  if fss_pre_activation_receipts_contain_other_boot "$pre_activation_receipts" "$current_boot"; then
    FSS_VERDICT_TAGS=$(fss_append_tag "$FSS_VERDICT_TAGS" "PRE_ACTIVATION_ARCHIVE")
    FSS_VERDICT_TAGS=$(fss_append_tag "$FSS_VERDICT_TAGS" "PRE_ACTIVATION_STALE")
    pre_activation_stale=1
  fi
  if fss_unclean_shutdown_receipts_contain_other_boot "$unclean_shutdown_receipts" "$current_boot"; then
    FSS_VERDICT_TAGS=$(fss_append_tag "$FSS_VERDICT_TAGS" "UNCLEAN_SHUTDOWN")
    FSS_VERDICT_TAGS=$(fss_append_tag "$FSS_VERDICT_TAGS" "UNCLEAN_SHUTDOWN_STALE")
    unclean_stale=1
  fi

  if [ -n "$expected_pre" ]; then
    allowed_list=$(fss_append_unique_line "$allowed_list" "$expected_pre")
  fi
  allowed_list=$(fss_merge_path_lists "$allowed_list" "$recovery_paths")
  allowed_list=$(fss_merge_path_lists "$allowed_list" "$pre_activation_paths")
  allowed_list=$(fss_merge_path_lists "$allowed_list" "$unclean_paths")

  # Carve a journald-attested, content-receipted unclean "system.journal~" corpse
  # out of the fatal active-system set into the archived-exception track. The live
  # system.journal has no '~', so it can never match an unclean receipt path and is
  # never carved out; an unmatched .journal~ stays fatal. Receipts arrive already
  # content-filtered (fss_filter_valid_receipts), so a substituted corpse has no
  # surviving receipt -> not carved -> fails closed.
  if [ -n "$FSS_ACTIVE_SYSTEM_FAILURES" ] && [ -n "$unclean_paths" ]; then
    local active_keep="" active_line apath
    while IFS= read -r active_line || [ -n "$active_line" ]; do
      [ -n "$active_line" ] || continue
      apath="${active_line#FAIL: }"
      apath="${apath%% *}"
      case "$apath" in
      *.journal~)
        if fss_path_list_contains "$unclean_paths" "$apath"; then
          FSS_ARCHIVED_SYSTEM_FAILURES=$(fss_append_line "$FSS_ARCHIVED_SYSTEM_FAILURES" "$active_line")
          continue
        fi
        ;;
      esac
      active_keep=$(fss_append_line "$active_keep" "$active_line")
    done <<<"$FSS_ACTIVE_SYSTEM_FAILURES"
    FSS_ACTIVE_SYSTEM_FAILURES="$active_keep"
  fi

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
          exception_seen=1
        fi
        if boot=$(fss_receipt_boot_for_path "$recovery_receipts" "$path"); then
          FSS_VERDICT_TAGS=$(fss_append_tag "$FSS_VERDICT_TAGS" "RECOVERY_ARCHIVE")
          recovery_seen=1
          exception_seen=1
          if [ -n "$current_boot" ] && [ -n "$boot" ] && [ "$boot" != "$current_boot" ]; then
            FSS_VERDICT_TAGS=$(fss_append_tag "$FSS_VERDICT_TAGS" "RECOVERY_STALE")
            recovery_stale=1
          fi
        fi
        if boot=$(fss_pre_activation_boot_for_path "$pre_activation_receipts" "$path"); then
          FSS_VERDICT_TAGS=$(fss_append_tag "$FSS_VERDICT_TAGS" "PRE_ACTIVATION_ARCHIVE")
          pre_activation_seen=1
          exception_seen=1
          if [ -n "$current_boot" ] && [ -n "$boot" ] && [ "$boot" != "$current_boot" ]; then
            FSS_VERDICT_TAGS=$(fss_append_tag "$FSS_VERDICT_TAGS" "PRE_ACTIVATION_STALE")
            pre_activation_stale=1
          fi
        fi
        if boot=$(fss_unclean_shutdown_boot_for_path "$unclean_shutdown_receipts" "$path"); then
          FSS_VERDICT_TAGS=$(fss_append_tag "$FSS_VERDICT_TAGS" "UNCLEAN_SHUTDOWN")
          unclean_seen=1
          exception_seen=1
          if [ -n "$current_boot" ] && [ -n "$boot" ] && [ "$boot" != "$current_boot" ]; then
            FSS_VERDICT_TAGS=$(fss_append_tag "$FSS_VERDICT_TAGS" "UNCLEAN_SHUTDOWN_STALE")
            unclean_stale=1
          fi
        fi
      done <<<"$archived_paths"
    else
      FSS_VERDICT=fail
      FSS_VERDICT_REASON="archived system journal failures outside allowlist"
      return 0
    fi
  fi

  if [ "$FSS_FILESYSTEM_RESTRICTION" = 1 ]; then
    FSS_VERDICT=warning
    FSS_VERDICT_REASON="filesystem restrictions encountered"
    return 0
  fi

  if [ "$archived_allowed" = 1 ] && [ -z "$FSS_USER_FAILURES" ]; then
    if [ "$pre_activation_stale" = 1 ]; then
      FSS_VERDICT=warning
      FSS_VERDICT_REASON="insecure boot logs from an earlier boot"
    elif [ "$recovery_stale" = 1 ]; then
      FSS_VERDICT=warning
      FSS_VERDICT_REASON="recovery archive from an earlier boot"
    elif [ "$unclean_stale" = 1 ]; then
      FSS_VERDICT=warning
      FSS_VERDICT_REASON="unclean-shutdown journal from an earlier boot"
    elif [ "$pre_activation_seen" = 1 ]; then
      FSS_VERDICT=verified-with-exception
      FSS_VERDICT_REASON="recorded insecure boot logs (current boot)"
    elif [ "$recovery_seen" = 1 ]; then
      FSS_VERDICT=verified-with-exception
      FSS_VERDICT_REASON="recorded recovery archive (current boot)"
    elif [ "$unclean_seen" = 1 ]; then
      FSS_VERDICT=verified-with-exception
      FSS_VERDICT_REASON="recorded unclean-shutdown journal (current boot)"
    else
      FSS_VERDICT=verified-with-exception
      FSS_VERDICT_REASON="recorded archived-system exceptions only"
    fi
    return 0
  fi

  if [ -n "$FSS_USER_FAILURES" ]; then
    FSS_VERDICT=warning
    if [ "$exception_seen" = 1 ]; then
      FSS_VERDICT_REASON="archived-system exceptions with user journal exceptions"
    else
      FSS_VERDICT_REASON="user journal exceptions only"
    fi
    return 0
  fi

  if [ -n "$FSS_TEMP_FAILURES" ]; then
    FSS_VERDICT=warning
    FSS_VERDICT_REASON="temporary journal files ignored"
    return 0
  fi

  if [ "$verify_exit" != 0 ]; then
    FSS_VERDICT_TAGS=$(fss_append_tag "$FSS_VERDICT_TAGS" "VERIFY_EXIT_UNCLASSIFIED")
    FSS_VERDICT=fail
    FSS_VERDICT_REASON="journalctl verify exited nonzero without a classified exception"
    return 0
  fi

  # A valid stale receipt remains on disk and journalctl emitted no failure for it:
  # structurally readable but non-FSS-trusted logs left over from an earlier boot.
  # Surface as a warning even if this boot also has an expected receipt.
  if [ "$pre_activation_stale" = 1 ]; then
    FSS_VERDICT_TAGS=$(fss_append_tag "$FSS_VERDICT_TAGS" "PRE_ACTIVATION_ARCHIVE")
    FSS_VERDICT_TAGS=$(fss_append_tag "$FSS_VERDICT_TAGS" "PRE_ACTIVATION_STALE")
    FSS_VERDICT=warning
    FSS_VERDICT_REASON="insecure boot logs from an earlier boot"
    return 0
  fi

  if [ "$unclean_stale" = 1 ]; then
    FSS_VERDICT_TAGS=$(fss_append_tag "$FSS_VERDICT_TAGS" "UNCLEAN_SHUTDOWN")
    FSS_VERDICT_TAGS=$(fss_append_tag "$FSS_VERDICT_TAGS" "UNCLEAN_SHUTDOWN_STALE")
    FSS_VERDICT=warning
    FSS_VERDICT_REASON="unclean-shutdown journal from an earlier boot"
    return 0
  fi

  if fss_pre_activation_receipts_contain_boot "$pre_activation_receipts" "$current_boot"; then
    FSS_VERDICT_TAGS=$(fss_append_tag "$FSS_VERDICT_TAGS" "PRE_ACTIVATION_ARCHIVE")
    FSS_VERDICT=verified-with-exception
    FSS_VERDICT_REASON="recorded insecure boot logs (current boot)"
    return 0
  fi

  if fss_unclean_shutdown_receipts_contain_boot "$unclean_shutdown_receipts" "$current_boot"; then
    FSS_VERDICT_TAGS=$(fss_append_tag "$FSS_VERDICT_TAGS" "UNCLEAN_SHUTDOWN")
    FSS_VERDICT=verified-with-exception
    FSS_VERDICT_REASON="recorded unclean-shutdown journal (current boot)"
    return 0
  fi

  # shellcheck disable=SC2034  # read by consumers that source this library
  FSS_VERDICT=verified
  # shellcheck disable=SC2034
  FSS_VERDICT_REASON=""
}
