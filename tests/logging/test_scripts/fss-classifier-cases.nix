# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Executable specification for fss-verify-classifier.sh: the verification policy
# matrix and the clock-jump / re-key predicates. Takes the classifier path as $1,
# so the same table runs as checks.x86_64-linux.fss-classifier-unit against the
# repo file and inside logging-fss against the installed /etc copy.
{
  writeShellApplication,
  coreutils,
  gnugrep,
  gawk,
}:
writeShellApplication {
  name = "fss-classifier-cases";
  runtimeInputs = [
    coreutils
    gnugrep
    gawk
  ];
  # Sourced from a runtime argument, so shellcheck sees neither the definitions
  # this file calls (SC1090/SC1091) nor the colours it consumes (SC2034).
  excludeShellChecks = [
    "SC1090"
    "SC1091"
    "SC2034"
  ];
  text = ''
    CLASSIFIER="''${1:-/etc/fss-verify-classifier.sh}"
    if [ ! -r "$CLASSIFIER" ]; then
      echo "fss-classifier-cases: no readable classifier at $CLASSIFIER" >&2
      exit 1
    fi
    source "$CLASSIFIER"

    # fss_log latches the colours once, at source time, from fd 1 -- and a nix
    # builder's stdout is a tty where a VM test's is a pipe. Pin them.
    RED=""
    GREEN=""
    YELLOW=""
    NC=""

    # Assert that classifying $sample and running policy yields $want.
    # Usage: assert_verdict <want> <sample> [pre] [recovery_receipts] [pre_activation_receipts] [boot] [verify_exit]
    assert_verdict() {
      local want="$1" sample="$2" pre="''${3:-}" recov="''${4:-}" receipts="''${5:-}" boot="''${6:-}" verify_exit="''${7:-0}" unclean="''${8:-}"
      fss_classify_verify_output "$sample"
      fss_verify_policy_decision "$pre" "$recov" "$receipts" "$boot" "$verify_exit" "$unclean"
      if [ "$FSS_VERDICT" != "$want" ]; then
        printf "verdict mismatch: want=%s got=%s reason=%s tags=%s sample=%s\n" \
          "$want" "$FSS_VERDICT" "$FSS_VERDICT_REASON" "$FSS_VERDICT_TAGS" "$sample" >&2
        return 1
      fi
    }

    # Build a synthetic pre-activation receipt record for path and boot id.
    mkreceipt() {
      printf "v1\t%s\t111\t2048\t%s\t1700000000\tdeadbeef\tpre-activation-rotation\tevt" "$1" "$2"
    }

    mkuncleanreceipt() {
      printf "v1\t%s\t111\t2048\t%s\t1700000000\tdeadbeef\tunclean-shutdown\tevt" "$1" "$2"
    }

    # A bare `! assertion` is exempt from errexit (SC2251), so it silently
    # passes whatever it claims to refute. Negative cases use these instead.
    refute() {
      if "$@" >/dev/null 2>&1; then
        printf "refute: expected failure, got success: %s\n" "$*" >&2
        exit 1
      fi
    }

    refute_contains() {
      if printf "%s" "$1" | grep -Fq -- "$2"; then
        printf "refute_contains: unexpectedly found %s in [%s]\n" "$2" "$1" >&2
        exit 1
      fi
    }

    CURBOOT="boot-current"
    ACTIVE="/var/log/journal/mid/system.journal"
    ALLOWED_ARCHIVE="/var/log/journal/mid/system@0000000000000001-0000000000000002.journal"
    RECOVERY_ARCHIVE="/var/log/journal/mid/system@0000000000000005-0000000000000006.journal"
    STALE_RECOVERY_ARCHIVE="/var/log/journal/mid/system@0000000000000011-0000000000000012.journal"
    PRE_ACTIVATION_ARCHIVE="/var/log/journal/mid/system@0000000000000007-0000000000000008.journal"
    STALE_PRE_ACTIVATION_ARCHIVE="/var/log/journal/mid/system@0000000000000009-0000000000000010.journal"
    UNEXPECTED_ARCHIVE="/var/log/journal/mid/system@0000000000000003-0000000000000004.journal"
    USER_JOURNAL="/var/log/journal/mid/user-1000@0000000000000001-0000000000000002.journal"
    TEMP_JOURNAL="/var/log/journal/mid/custom.journal~"
    ACTIVE_TEMP_JOURNAL="/var/log/journal/mid/system.journal~"
    ARCHIVED_TEMP_JOURNAL="/var/log/journal/mid/system@0000000000000001-0000000000000002.journal~"
    OTHER="/var/log/journal/mid/custom.journal"

    # Trust transition matrix: these cases are the compact executable
    # specification for FSS verification policy.
    assert_verdict verified "PASS: $ACTIVE"

    assert_verdict fail "FAIL: $ACTIVE (Bad message)"
    [ -n "$FSS_ACTIVE_SYSTEM_FAILURES" ]

    assert_verdict warning \
      "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$PRE_ACTIVATION_ARCHIVE" "$ACTIVE")" \
      "" "" "$(mkreceipt "$PRE_ACTIVATION_ARCHIVE" "$CURBOOT")" "$CURBOOT"
    [ "$FSS_VERDICT_REASON" = "recorded insecure boot logs (current boot)" ]

    assert_verdict warning \
      "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$PRE_ACTIVATION_ARCHIVE" "$ACTIVE")" \
      "" "" "$(mkreceipt "$PRE_ACTIVATION_ARCHIVE" "boot-earlier")" "$CURBOOT"
    [ "$FSS_VERDICT_REASON" = "insecure boot logs from an earlier boot" ]

    assert_verdict fail \
      "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$PRE_ACTIVATION_ARCHIVE" "$ACTIVE")" \
      "" "" "" "$CURBOOT"
    [ "$FSS_VERDICT_REASON" = "archived system journal failures outside allowlist" ]

    assert_verdict warning "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$USER_JOURNAL" "$ACTIVE")"
    [ -n "$FSS_USER_FAILURES" ]
    [ -z "$FSS_ACTIVE_SYSTEM_FAILURES" ]

    assert_verdict warning \
      "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$ARCHIVED_TEMP_JOURNAL" "$ACTIVE")" \
      "" "" "" "$CURBOOT" 1 "$(mkuncleanreceipt "$ARCHIVED_TEMP_JOURNAL" "$CURBOOT")"
    [ "$FSS_VERDICT_REASON" = "recorded unclean-shutdown journal (current boot)" ]

    assert_verdict fail \
      "FAIL: $ACTIVE (Bad message)" \
      "" "" "" "$CURBOOT" 1 "$(mkuncleanreceipt "$ARCHIVED_TEMP_JOURNAL" "$CURBOOT")"
    [ "$FSS_VERDICT_REASON" = "active system journal verification failed" ]

    assert_verdict warning "$(printf "FAIL: %s (Virheellinen viesti)\nPASS: %s" "$USER_JOURNAL" "$ACTIVE")"
    [ -n "$FSS_USER_FAILURES" ]
    refute_contains "$FSS_REASON_TAGS" "BAD_MESSAGE"

    # Active system failure → fail
    assert_verdict fail "FAIL: $ACTIVE (Bad message)"
    [ "$FSS_REASON_TAGS" = "BAD_MESSAGE" ]

    # Clean output → verified
    assert_verdict verified "PASS: $ACTIVE"

    # Clean output with a current-boot pre-activation receipt still means
    # warning: those entries were structurally readable but not FSS-trusted,
    # and the receipt backing the exception is itself unauthenticated.
    assert_verdict warning \
      "PASS: $ACTIVE" \
      "" "" "$(mkreceipt "$PRE_ACTIVATION_ARCHIVE" "$CURBOOT")" "$CURBOOT"
    [ "$FSS_VERDICT_REASON" = "recorded insecure boot logs (current boot)" ]
    printf "%s" "$FSS_VERDICT_TAGS" | grep -F "PRE_ACTIVATION_ARCHIVE"

    # Clean output with only an EARLIER-boot pre-activation receipt → warning:
    # old unsealed boot logs lingering on disk must not report as fully verified.
    assert_verdict warning \
      "PASS: $ACTIVE" \
      "" "" "$(mkreceipt "$PRE_ACTIVATION_ARCHIVE" "boot-earlier")" "$CURBOOT"
    [ "$FSS_VERDICT_REASON" = "insecure boot logs from an earlier boot" ]
    printf "%s" "$FSS_VERDICT_TAGS" | grep -F "PRE_ACTIVATION_STALE"

    # Clean output with both current and earlier-boot receipts → warning:
    # stale retained evidence must not be hidden by a new current-boot receipt.
    MIXED_PRE_ACTIVATION_RECEIPTS="$(printf "%s\n%s" \
      "$(mkreceipt "$PRE_ACTIVATION_ARCHIVE" "$CURBOOT")" \
      "$(mkreceipt "$STALE_PRE_ACTIVATION_ARCHIVE" "boot-earlier")")"
    assert_verdict warning \
      "PASS: $ACTIVE" \
      "" "" "$MIXED_PRE_ACTIVATION_RECEIPTS" "$CURBOOT"
    [ "$FSS_VERDICT_REASON" = "insecure boot logs from an earlier boot" ]
    printf "%s" "$FSS_VERDICT_TAGS" | grep -F "PRE_ACTIVATION_STALE"

    # Allowed archive only → warning (matches pre-FSS allowlist)
    assert_verdict warning \
      "$(printf "FAIL: %s (Input/output error)\nPASS: %s" "$ALLOWED_ARCHIVE" "$ACTIVE")" \
      "$ALLOWED_ARCHIVE"
    [ "$FSS_REASON_TAGS" = "INPUT_OUTPUT_ERROR" ]
    [ "$FSS_VERDICT_REASON" = "recorded archived-system exceptions only" ]
    printf "%s" "$FSS_VERDICT_TAGS" | grep -F "PRE_FSS_ARCHIVE"
    fss_matches_only_expected_archived_system_failure "$ALLOWED_ARCHIVE"

    # Legacy path-only recovery archive → fail (no longer trusted)
    assert_verdict fail \
      "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$RECOVERY_ARCHIVE" "$ACTIVE")" \
      "" "$(printf "%s\n%s" "$RECOVERY_ARCHIVE" "$RECOVERY_ARCHIVE")"

    # Current-boot recovery receipt → warning
    assert_verdict warning \
      "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$RECOVERY_ARCHIVE" "$ACTIVE")" \
      "" "$(mkreceipt "$RECOVERY_ARCHIVE" "$CURBOOT")" "" "$CURBOOT"
    [ "$FSS_VERDICT_REASON" = "recorded recovery archive (current boot)" ]
    printf "%s" "$FSS_VERDICT_TAGS" | grep -F "RECOVERY_ARCHIVE"

    # Earlier-boot recovery receipt → warning
    assert_verdict warning \
      "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$STALE_RECOVERY_ARCHIVE" "$ACTIVE")" \
      "" "$(mkreceipt "$STALE_RECOVERY_ARCHIVE" "boot-earlier")" "" "$CURBOOT"
    [ "$FSS_VERDICT_REASON" = "recovery archive from an earlier boot" ]
    printf "%s" "$FSS_VERDICT_TAGS" | grep -F "RECOVERY_STALE"

    # Current-boot pre-activation receipt → warning
    assert_verdict warning \
      "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$PRE_ACTIVATION_ARCHIVE" "$ACTIVE")" \
      "" "" "$(mkreceipt "$PRE_ACTIVATION_ARCHIVE" "$CURBOOT")" "$CURBOOT"
    [ "$FSS_VERDICT_REASON" = "recorded insecure boot logs (current boot)" ]
    printf "%s" "$FSS_VERDICT_TAGS" | grep -F "PRE_ACTIVATION_ARCHIVE"
    refute_contains "$FSS_VERDICT_TAGS" "PRE_ACTIVATION_STALE"

    # Earlier-boot pre-activation receipt → warning (evidenced but stale)
    assert_verdict warning \
      "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$PRE_ACTIVATION_ARCHIVE" "$ACTIVE")" \
      "" "" "$(mkreceipt "$PRE_ACTIVATION_ARCHIVE" "boot-earlier")" "$CURBOOT"
    [ "$FSS_VERDICT_REASON" = "insecure boot logs from an earlier boot" ]
    printf "%s" "$FSS_VERDICT_TAGS" | grep -F "PRE_ACTIVATION_STALE"

    # Archived failure with no matching receipt → fail (unrecorded/substituted)
    assert_verdict fail \
      "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$PRE_ACTIVATION_ARCHIVE" "$ACTIVE")" \
      "" "" "" "$CURBOOT"

    # Unexpected archive → fail
    assert_verdict fail \
      "$(printf "FAIL: %s (Input/output error)\nPASS: %s" "$UNEXPECTED_ARCHIVE" "$ACTIVE")" \
      "$ALLOWED_ARCHIVE" "$(mkreceipt "$RECOVERY_ARCHIVE" "$CURBOOT")" "" "$CURBOOT"

    # Allowed + recovery archives together → warning
    assert_verdict warning \
      "$(printf "FAIL: %s (Bad message)\nFAIL: %s (Bad message)" "$ALLOWED_ARCHIVE" "$RECOVERY_ARCHIVE")" \
      "$ALLOWED_ARCHIVE" "$(mkreceipt "$RECOVERY_ARCHIVE" "$CURBOOT")" "" "$CURBOOT"

    # Allowed + unexpected archive → fail (allowlist miss on one path)
    assert_verdict fail \
      "$(printf "FAIL: %s (Bad message)\nFAIL: %s (Bad message)" "$ALLOWED_ARCHIVE" "$UNEXPECTED_ARCHIVE")" \
      "$ALLOWED_ARCHIVE" "$(mkreceipt "$RECOVERY_ARCHIVE" "$CURBOOT")" "" "$CURBOOT"

    # Filesystem restrictions make otherwise allowlisted verifies a warning
    assert_verdict warning "Failed to open journal file: Read-only file system"
    [ "$FSS_VERDICT_REASON" = "filesystem restrictions encountered" ]

    assert_verdict warning \
      "$(printf "Failed to open journal file: Read-only file system\nFAIL: %s (Bad message)" "$ALLOWED_ARCHIVE")" \
      "$ALLOWED_ARCHIVE"
    [ "$FSS_VERDICT_REASON" = "filesystem restrictions encountered" ]

    assert_verdict warning \
      "$(printf "Failed to open journal file: Permission denied\nFAIL: %s (Bad message)" "$RECOVERY_ARCHIVE")" \
      "" "$(mkreceipt "$RECOVERY_ARCHIVE" "$CURBOOT")" "" "$CURBOOT"
    [ "$FSS_VERDICT_REASON" = "filesystem restrictions encountered" ]

    assert_verdict fail \
      "$(printf "Failed to open journal file: Read-only file system\nFAIL: %s (Bad message)" "$UNEXPECTED_ARCHIVE")" \
      "$ALLOWED_ARCHIVE" "$(mkreceipt "$RECOVERY_ARCHIVE" "$CURBOOT")" "" "$CURBOOT"

    # User journal failure alone → warning (non-fatal)
    assert_verdict warning "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$USER_JOURNAL" "$ACTIVE")"
    [ -n "$FSS_USER_FAILURES" ]
    [ -z "$FSS_ACTIVE_SYSTEM_FAILURES" ]

    # Localized journalctl reason text still classifies by failed path.
    assert_verdict warning "$(printf "FAIL: %s (Virheellinen viesti)\nPASS: %s" "$USER_JOURNAL" "$ACTIVE")"
    [ -n "$FSS_USER_FAILURES" ]
    [ -z "$FSS_ACTIVE_SYSTEM_FAILURES" ]
    refute_contains "$FSS_REASON_TAGS" "BAD_MESSAGE"

    assert_verdict fail "FAIL: $ACTIVE (Virheellinen viesti)"
    [ -n "$FSS_ACTIVE_SYSTEM_FAILURES" ]
    [ -z "$FSS_REASON_TAGS" ]

    # User journal with corruption diagnostics → warning
    assert_verdict warning "$(printf "2cb2e0: Tag failed verification\nFile corruption detected at %s:2929376 (of 8388608 bytes, 34%%).\nFAIL: %s (Bad message)\nPASS: %s" "$USER_JOURNAL" "$USER_JOURNAL" "$ACTIVE")"

    # Temp journal failure → warning (ignored leftover)
    assert_verdict warning "FAIL: $TEMP_JOURNAL (Bad message)"
    [ -n "$FSS_TEMP_FAILURES" ]

    # Critical system journals renamed with ~ retain their base severity.
    assert_verdict fail "FAIL: $ACTIVE_TEMP_JOURNAL (Bad message)"
    [ -n "$FSS_ACTIVE_SYSTEM_FAILURES" ]
    assert_verdict fail "FAIL: $ARCHIVED_TEMP_JOURNAL (Bad message)"
    [ -n "$FSS_ARCHIVED_SYSTEM_FAILURES" ]

    # Unclean-shutdown receipting (journald-attested, content-bound). An
    # archived .journal~ corpse with a current-boot unclean receipt is an
    # expected exception, not a hard fail.
    assert_verdict warning \
      "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$ARCHIVED_TEMP_JOURNAL" "$ACTIVE")" \
      "" "" "" "$CURBOOT" 1 "$(mkuncleanreceipt "$ARCHIVED_TEMP_JOURNAL" "$CURBOOT")"
    [ "$FSS_VERDICT_REASON" = "recorded unclean-shutdown journal (current boot)" ]
    printf "%s" "$FSS_VERDICT_TAGS" | grep -F "UNCLEAN_SHUTDOWN"

    # The active system.journal~ corpse is carved out of the fatal active-system
    # set only with a matching content-bound receipt.
    assert_verdict warning \
      "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$ACTIVE_TEMP_JOURNAL" "$ACTIVE")" \
      "" "" "" "$CURBOOT" 1 "$(mkuncleanreceipt "$ACTIVE_TEMP_JOURNAL" "$CURBOOT")"

    # The LIVE system.journal (no ~) is NEVER exempted, even with an unclean
    # receipt present for some other path.
    assert_verdict fail \
      "FAIL: $ACTIVE (Bad message)" \
      "" "" "" "$CURBOOT" 1 "$(mkuncleanreceipt "$ARCHIVED_TEMP_JOURNAL" "$CURBOOT")"

    # An unmatched system@*.journal~ (no receipt) still fails closed.
    assert_verdict fail \
      "FAIL: $ARCHIVED_TEMP_JOURNAL (Bad message)" \
      "" "" "" "$CURBOOT" 1 ""

    # Earlier-boot unclean receipt → warning (stale must not pass forever).
    assert_verdict warning \
      "$(printf "FAIL: %s (Bad message)\nPASS: %s" "$ARCHIVED_TEMP_JOURNAL" "$ACTIVE")" \
      "" "" "" "$CURBOOT" 1 "$(mkuncleanreceipt "$ARCHIVED_TEMP_JOURNAL" "boot-earlier")"
    printf "%s" "$FSS_VERDICT_TAGS" | grep -F "UNCLEAN_SHUTDOWN_STALE"

    # Clean output + current-boot unclean receipt → warning.
    assert_verdict warning \
      "PASS: $ACTIVE" \
      "" "" "" "$CURBOOT" 0 "$(mkuncleanreceipt "$ARCHIVED_TEMP_JOURNAL" "$CURBOOT")"

    # Other/unclassified journal → fail
    assert_verdict fail "FAIL: $OTHER (Bad message)"
    [ -n "$FSS_OTHER_FAILURES" ]

    # Key parse + missing key → fail
    assert_verdict fail "$(printf "Failed to parse seed.\nFAIL: %s (Required key not available)" "$ACTIVE")"
    [ "$FSS_KEY_PARSE_ERROR" -eq 1 ]
    [ "$FSS_KEY_REQUIRED_ERROR" -eq 1 ]
    [ "$FSS_REASON_TAGS" = "KEY_PARSE_ERROR,KEY_MISSING" ]

    # Empty input → verified (no findings)
    assert_verdict verified ""
    [ -z "$FSS_REASON_TAGS" ]
    [ -z "$FSS_FAIL_LINES" ]

    # Nonzero verify exit with no classified exception → fail
    assert_verdict fail "" "" "" "" "$CURBOOT" 42
    [ "$FSS_VERDICT_REASON" = "journalctl verify exited nonzero without a classified exception" ]
    printf "%s" "$FSS_VERDICT_TAGS" | grep -F "VERIFY_EXIT_UNCLASSIFIED"

    # Content-bound receipt filtering against the live filesystem.
    real=$(mktemp)
    printf "original" > "$real"
    rino=$(stat -c %i "$real"); rsz=$(stat -c %s "$real"); rsha=$(sha256sum "$real" | cut -d" " -f1)
    good=$(printf "v1\t%s\t%s\t%s\t%s\t1\t%s\tpre-activation-rotation\tevt" "$real" "$rino" "$rsz" "$CURBOOT" "$rsha")
    [ "$(fss_filter_valid_receipts "$good")" = "$good" ]
    [ -z "$(fss_pre_activation_receipt_mismatches "$good")" ]
    weak=$(printf "v1\t%s\t%s\t%s\t%s\t1\t-\tpre-activation-rotation\tevt" "$real" "$rino" "$rsz" "$CURBOOT")
    [ -z "$(fss_filter_valid_receipts "$weak")" ]
    [ -z "$(fss_pre_activation_receipt_mismatches "$weak")" ]
    # Substituted content (size + hash change) → receipt dropped
    printf "tampered-and-longer" > "$real"
    [ "$(fss_pre_activation_receipt_mismatches "$good")" = "$real" ]
    [ -z "$(fss_filter_valid_receipts "$good")" ]
    # Missing file → receipt dropped
    rm -f "$real"
    [ -z "$(fss_pre_activation_receipt_mismatches "$good")" ]
    [ -z "$(fss_filter_valid_receipts "$good")" ]

    # Bucket classification and dedup of unique fail paths
    MIXED=$(printf "FAIL: %s (Bad message)\nFAIL: %s (Bad message)\nFAIL: %s (Bad message)\nFAIL: %s (Bad message)\nFAIL: %s (Bad message)\nFAIL: %s (Bad message)" \
      "$ACTIVE" "$ACTIVE" "$ALLOWED_ARCHIVE" "$USER_JOURNAL" "$TEMP_JOURNAL" "$OTHER")
    [ "$(fss_count_nonempty_lines "$(fss_unique_fail_paths_from_output "$MIXED")")" -eq 5 ]
    [ "$(fss_failure_bucket_for_path "$ACTIVE")" = "active-system" ]
    [ "$(fss_failure_bucket_for_path "$ALLOWED_ARCHIVE")" = "archived-system" ]
    [ "$(fss_failure_bucket_for_path "$USER_JOURNAL")" = "user-journal" ]
    [ "$(fss_failure_bucket_for_path "$TEMP_JOURNAL")" = "temp" ]
    [ "$(fss_failure_bucket_for_path "$ACTIVE_TEMP_JOURNAL")" = "active-system" ]
    [ "$(fss_failure_bucket_for_path "$ARCHIVED_TEMP_JOURNAL")" = "archived-system" ]
    [ "$(fss_failure_bucket_for_path "$OTHER")" = "other" ]

    # Level names are case-insensitive; colour only when the vars are set.
    log_output=$(fss_log pass "pass message"
                 fss_log FAIL "fail message"
                 fss_log warning "warn message"
                 fss_log info "info message"
                 fss_log_block < <(printf "%s\n" "block line 1" "block line 2"))
    expected=$(printf "[PASS] pass message\n[FAIL] fail message\n[WARN] warn message\n[INFO] info message\nblock line 1\nblock line 2")
    [ "$log_output" = "$expected" ]

    RED="<r>"
    GREEN="<g>"
    NC="<n>"
    coloured=$(fss_log pass "pass message"
               fss_log FAIL "fail message"
               fss_log info "info message")
    expected_coloured=$(printf "<g>[PASS]<n> pass message\n<r>[FAIL]<n> fail message\n[INFO] info message")
    [ "$coloured" = "$expected_coloured" ]
    RED=""
    GREEN=""
    NC=""

    # State-file readers trim whitespace and dedupe.
    state=$(mktemp)
    printf "  %s \n" "$ALLOWED_ARCHIVE" > "$state"
    [ "$(fss_read_recorded_pre_fss_archive "$state")" = "$ALLOWED_ARCHIVE" ]
    rm -f "$state"
    [ -z "$(fss_read_recorded_pre_fss_archive "$state")" ]

    list=$(mktemp)
    printf " %s \n%s\n%s\n" "$ALLOWED_ARCHIVE" "$RECOVERY_ARCHIVE" "$RECOVERY_ARCHIVE" > "$list"
    [ "$(fss_read_recorded_archive_list "$list")" = "$(printf "%s\n%s" "$ALLOWED_ARCHIVE" "$RECOVERY_ARCHIVE")" ]
    rm -f "$list"

    # ------------------------------------------------------------------
    # Clock-jump and FSS re-key predicates.
    # ------------------------------------------------------------------

    # journald's own backward-jump attestations, from --output=short-unix.
    JUMP_LINES=$(printf "%s\n" \
      "1700000000.123456 h systemd-journald[1]: Time jumped backwards, rotating." \
      "1700000042.000000 h systemd-journald[1]: Realtime clock jumped backwards relative to last journal entry, rotating." \
      "1700000111.000000 h systemd-journald[1]: Journal started")
    [ "$(printf "%s\n" "$JUMP_LINES" | fss_time_jump_epochs_from_lines)" = "$(printf "1700000000\n1700000042")" ]

    # A monotonic jump does not move the realtime clock, so it cannot poison the
    # FSPRG sealing epoch and must not be counted as a jump.
    MONOTONIC="1700000099.0 h systemd-journald[1]: Monotonic clock jumped backwards relative to last journal entry with the same boot ID, rotating."
    [ -z "$(printf "%s\n" "$MONOTONIC" | fss_time_jump_epochs_from_lines)" ]
    [ -z "$(printf "" | fss_time_jump_epochs_from_lines)" ]

    # Archive mtime windowed against attested jump epochs.
    EPOCHS=$(printf "1700000000\n1700000500")
    fss_mtime_matches_time_jump_epoch 1700000010 "$EPOCHS"
    fss_mtime_matches_time_jump_epoch 1699999990 "$EPOCHS"
    refute fss_mtime_matches_time_jump_epoch 1700000011 "$EPOCHS"
    refute fss_mtime_matches_time_jump_epoch 1700000250 "$EPOCHS"
    refute fss_mtime_matches_time_jump_epoch 1700000010 ""

    # Future-tag extraction from "Older entry after newer tag (A < B)".
    [ -z "$(fss_max_future_tag_epoch_us "")" ]
    [ -z "$(fss_max_future_tag_epoch_us "PASS: $ACTIVE")" ]
    [ "$(fss_max_future_tag_epoch_us \
      "0002a8: Older entry after newer tag (1700000000000000 < 1800000000000000)")" \
      = 1800000000000000 ]

    # Highest across lines, regardless of order.
    [ "$(fss_max_future_tag_epoch_us "$(printf "%s\n%s" \
      "0004b0: Older entry after newer tag (1 < 1900000000000000)" \
      "0002a8: Older entry after newer tag (1 < 1800000000000000)")")" \
      = 1900000000000000 ]

    # Sibling diagnostics carry unrelated numbers: matching one would re-key on
    # a condition that is not a backward clock step.
    [ -z "$(fss_max_future_tag_epoch_us \
      "0002a8: tag/entry realtime timestamp out of synchronization (5 >= 4)")" ]
    [ -z "$(fss_max_future_tag_epoch_us \
      "0002a8: Entry realtime (1, x) is too early with respect to tag (2, y)")" ]
    [ -z "$(fss_max_future_tag_epoch_us \
      "0002a8: Epoch sequence out of synchronization (3 < 4)")" ]
    [ -z "$(fss_max_future_tag_epoch_us "0002a8: Tag failed verification")" ]

    # Wider than int64: dropped, since the caller does arithmetic on it.
    [ -z "$(fss_max_future_tag_epoch_us \
      "0002a8: Older entry after newer tag (1 < 99999999999999999999999999)")" ]

    # The margin covers a tag legitimately one sealing interval ahead; a smaller
    # step self-heals once wall time passes the tag's window.
    NOW_US=1700000000000000
    MARGIN_US=300000000
    refute fss_time_poisoned_sealing_epoch_us \
      "x: Older entry after newer tag (1 < $((NOW_US + 299000000)))" \
      "$NOW_US" "$MARGIN_US" >/dev/null
    refute fss_time_poisoned_sealing_epoch_us \
      "x: Older entry after newer tag (1 < $((NOW_US + MARGIN_US)))" \
      "$NOW_US" "$MARGIN_US" >/dev/null
    [ "$(fss_time_poisoned_sealing_epoch_us \
      "x: Older entry after newer tag (1 < $((NOW_US + 301000000)))" \
      "$NOW_US" "$MARGIN_US")" = "$((NOW_US + 301000000))" ]
    refute fss_time_poisoned_sealing_epoch_us "PASS: $ACTIVE" "$NOW_US" "$MARGIN_US" >/dev/null
    refute fss_time_poisoned_sealing_epoch_us "" "$NOW_US" "$MARGIN_US" >/dev/null

    # The stamp authorises discarding the key pair, so every arm matters.
    NOW=1700000000
    TTL=604800
    mkstamp() { printf "%s\t%s\tepochs" "$1" "$2"; }

    [ "$(fss_clock_jump_stamp_state "" "$CURBOOT" "$NOW" "$TTL")" = none ]
    [ "$(fss_clock_jump_stamp_state "$(mkstamp "$NOW" "$CURBOOT")" "$CURBOOT" "$NOW" "$TTL")" \
      = current-boot ]
    [ "$(fss_clock_jump_stamp_state "$(mkstamp "$NOW" "boot-earlier")" "$CURBOOT" "$NOW" "$TTL")" \
      = persisted-stamp ]
    [ "$(fss_clock_jump_stamp_state \
      "$(mkstamp $((NOW - TTL)) "boot-earlier")" "$CURBOOT" "$NOW" "$TTL")" = persisted-stamp ]
    [ "$(fss_clock_jump_stamp_state \
      "$(mkstamp $((NOW - TTL - 1)) "boot-earlier")" "$CURBOOT" "$NOW" "$TTL")" = expired ]

    # The stamp records the event that moves the clock, so it can read as
    # future-dated. Inside the window it counts; far outside it does not.
    [ "$(fss_clock_jump_stamp_state \
      "$(mkstamp $((NOW + 3600)) "boot-earlier")" "$CURBOOT" "$NOW" "$TTL")" = persisted-stamp ]
    [ "$(fss_clock_jump_stamp_state \
      "$(mkstamp $((NOW + TTL + 1)) "boot-earlier")" "$CURBOOT" "$NOW" "$TTL")" = expired ]

    # A malformed stamp must never read as an authorisation.
    [ "$(fss_clock_jump_stamp_state "notanepoch	$CURBOOT	e" "$CURBOOT" "$NOW" "$TTL")" = malformed ]
    [ "$(fss_clock_jump_stamp_state "	$CURBOOT	e" "$CURBOOT" "$NOW" "$TTL")" = malformed ]
    [ "$(fss_clock_jump_stamp_state "-5	$CURBOOT	e" "$CURBOOT" "$NOW" "$TTL")" = malformed ]

    # Live-write race vs real defect. Only the counter-mismatch family is
    # retryable, and only when nothing indicts the content.
    ACT="$FSS_ACTIVE_SYSTEM_FAILURES"
    assert_verdict fail "FAIL: $ACTIVE (Bad message)"
    ACT="$FSS_ACTIVE_SYSTEM_FAILURES"
    [ -n "$ACT" ]

    # All six variants systemd emits (journal-verify.c:1266-1315).
    for kind in Object Entry Data Field Tag "Entry array"; do
      fss_output_has_counter_mismatch "0000d0: $kind number mismatch (208 != 207)" \
        || { echo "counter mismatch not recognised: $kind" >&2; exit 1; }
      fss_active_failure_retryable "0000d0: $kind number mismatch (208 != 207)" "$ACT" \
        || { echo "should be retryable: $kind" >&2; exit 1; }
    done

    # The exact output observed on hardware.
    OBSERVED="$(printf '%s\n%s\n%s' \
      "0000d0: Data number mismatch (208 != 207)" \
      "File corruption detected at /var/log/journal/mid/system.journal:2997544 (of 8388608 bytes, 35%)." \
      "FAIL: $ACTIVE (Bad message)")"
    fss_active_failure_retryable "$OBSERVED" "$ACT"

    # Nothing else is retryable: no counter mismatch, no active failure, or a
    # signature that indicts the content.
    refute fss_output_has_counter_mismatch "FAIL: $ACTIVE (Bad message)"
    refute fss_active_failure_retryable "FAIL: $ACTIVE (Bad message)" "$ACT"
    refute fss_active_failure_retryable "0000d0: Data number mismatch (208 != 207)" ""
    for bad in "2cb2e0: Tag failed verification" \
               "0000d0: Hash value mismatch in hash entry 3 of 9" \
               "0002a8: Older entry after newer tag (1 < 2)" \
               "352a58: Epoch sequence not continuous (0 vs 0)" \
               "0002a8: tag/entry realtime timestamp out of synchronization (5 >= 4)"; do
      fss_output_has_tamper_signature "$bad" \
        || { echo "tamper signature not recognised: $bad" >&2; exit 1; }
      refute fss_active_failure_retryable \
        "$(printf '%s\n%s' "0000d0: Data number mismatch (208 != 207)" "$bad")" "$ACT"
    done

    echo "fss-classifier-cases: all cases passed against $CLASSIFIER"
  '';
}
