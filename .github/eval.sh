#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

################################################################################

# This script is a helper to evaluate flake outputs in github actions.

set -e # exit immediately if a command fails
set -E # exit immediately if a command fails (subshells)
set -u # treat unset variables as an error and exit
set -o pipefail # exit if any pipeline command fails

TMPDIR="$(mktemp -d --suffix .evaltmp)"
MYNAME=$(basename "$0")
RED='' NONE=''

################################################################################

usage () {
    echo ""
    echo "Usage: $MYNAME [-h] [-v] [-t EVAL_TARGETS] -j JOB_ID -m MAX_JOBS"
    echo ""
    echo "Helper to evaluate flake targets in github actions"
    echo ""
    echo "Options:"
    echo " -j    Set the instance JOB_ID: integer value between 0 and MAX_JOBS-1"
    echo " -m    Set the MAX_JOBS count: how many instances of this script will "
    echo "       be executed on different hosts (runners)"
    echo " -t    Filter evaluation targets (default='packages')"
    echo " -v    Set the script verbosity to DEBUG"
    echo " -h    Print this help message"
    echo ""
    echo "Examples:"
    echo ""
    echo "  Following four commands (combined) will evaluate flake outputs that "
    echo "  match the default filter 'packages' - each command should be executed"
    echo "  in its own github runner, thus splitting the eval work on "
    echo "  separate hosts allowing concurrent execution:"
    echo ""
    echo "    $MYNAME -j 0 -m 4"
    echo "    $MYNAME -j 1 -m 4"
    echo "    $MYNAME -j 2 -m 4"
    echo "    $MYNAME -j 3 -m 4"
    echo ""
}

################################################################################

on_exit () {
    rm -fr "$TMPDIR" # remove tmpdir
}

on_err () {
    kill 0 # kill the master shell and possible subshells
}

print_err () {
    printf "${RED}Error:${NONE} %b\n" "$1" >&2
}

argparse () {
    # Colorize output if stdout is to a terminal (and not to pipe or file)
    if [ -t 1 ]; then RED='\033[1;31m'; NONE='\033[0m'; fi
    # Parse arguments
    JOB_ID=""; MAX_JOBS=""; EVAL_TARGETS="packages"; OPTIND=1
    while getopts "hvj:m:t:" copt; do
        case "${copt}" in
            h)
                usage; exit 0 ;;
            v)
                set -x ;;
            t)
                EVAL_TARGETS="$OPTARG" ;;
            j)
                JOB_ID="$OPTARG"
                if ! [[ "$JOB_ID" == +([0-9]) ]]; then
                    print_err "'-j' expects a non-negative integer (got: '$JOB_ID')"
                    usage
                fi
                ;;
            m)
                MAX_JOBS="$OPTARG"
                if ! [[ "$MAX_JOBS" == +([0-9]) ]]; then
                    print_err "'-m' expects a non-negative integer (got: '$MAX_JOBS')"
                    usage
                fi
                ;;
            *)
                print_err "unrecognized option"; usage; exit 1 ;;
        esac
    done
    shift $((OPTIND-1))
    if [ -n "$*" ]; then
        print_err "unsupported positional argument(s): '$*'"; exit 1
    fi
    if [ -z "$JOB_ID" ]; then
        print_err "missing mandatory option (-j)"; usage; exit 1
    fi
    if [ -z "$MAX_JOBS" ]; then
        print_err "missing mandatory option (-m)"; usage; exit 1
    fi
    if [ "$JOB_ID" -ge "$MAX_JOBS" ]; then
        print_err "'-j' must be smaller than '-m'"; usage; exit 1
    fi
}

exit_unless_command_exists () {
    if ! command -v "$1" &>/dev/null; then
        print_err "command '$1' is not installed (Hint: are you inside a nix-shell?)"
        exit 1
    fi
}

################################################################################

evaluate () {
    job="$1"
    max_jobs="$2"
    filter="$3"
    echo "[+] Using filter: '$filter'"
    # Output all flake output names
    nix flake show --all-systems --json |\
      jq  '[paths(scalars) as $path | { ($path|join(".")): getpath($path) }] | add' \
      >"$TMPDIR/outs_all.txt"
    # Apply the given filter
    if ! grep -Po "${filter}\S*.name" "$TMPDIR/outs_all.txt" >"$TMPDIR/outs.txt"; then
        print_err "No flake outputs match filter: '$filter'"; exit 1
    fi
    # Remove the '.name' suffix
    sed -i "s/.name//" "$TMPDIR/outs.txt"
    # Read the attribute set names
    grep -oP ".*(?=\.)" "$TMPDIR/outs.txt" | sort | uniq >"$TMPDIR/attrs.txt"
    # Generate eval expression on the fly
    printf '%s\n' \
      "let" \
      "  flake = builtins.getFlake ("git+file://" + toString ./.);"\
      "  lib = (import flake.inputs.nixpkgs { }).lib;"\
      "in {" >"$TMPDIR/eval.nix"
    while read -r attrset; do
        mapfile -t attrs < <(grep "$attrset" "$TMPDIR/outs.txt" | rev | cut -d '.' -f1 | rev | sort | uniq)
        # Split the target attribute set so the evaluation work gets distributed
        # somewhat evenly between 'max_jobs' runners
        split_size=$(( ( ${#attrs[@]} + max_jobs - 1 ) / max_jobs ))
        # Select the attributes that will be evaluated by this runner
        start_index=$(( job * split_size ))
        split_attrs=("${attrs[@]:$start_index:$split_size}")
        if [ "${#split_attrs[@]}" -eq 0 ]; then
            continue
        fi
        # shellcheck disable=SC2129
        printf "  out_%s = lib.getAttrs [ " "$attrset" >>"$TMPDIR/eval.nix"
        printf " \"%s\" "  "${split_attrs[@]}" >>"$TMPDIR/eval.nix"
        printf " ] flake.%s;\n" "$attrset" >>"$TMPDIR/eval.nix"
    done < "$TMPDIR/attrs.txt"
    printf "}\n" >>"$TMPDIR/eval.nix"
    echo "[+] Evaluating nix expression:"
    cat "$TMPDIR/eval.nix"
    # Evaluate with nix-eval-jobs
    gcroot="$TMPDIR/gcroot"
    nix-eval-jobs \
      --accept-flake-config \
      --gc-roots-dir "$gcroot" \
      --force-recurse \
      --expr "$(cat "$TMPDIR/eval.nix")"
}

main () {
    trap on_exit EXIT
    trap on_err ERR
    echo "[+] Using tmpdir: '$TMPDIR'"
    argparse "$@"
    exit_unless_command_exists nix-eval-jobs
    exit_unless_command_exists jq
    evaluate "$JOB_ID" "$MAX_JOBS" "$EVAL_TARGETS"
}

main "$@"

################################################################################

