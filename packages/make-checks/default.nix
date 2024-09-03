# Copyright 2020 Jonas Chevalier
# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Shamelessly derived from https://github.com/numtide/nixpkgs-unfree/blob/main/ci.sh
#
# Check that all of the projects can be evaluated.
# This does not build any packages or run any tests, just evaluates the flake packages.
{
  writeShellApplication,
  nix-eval-jobs,
  jq,
  ...
}:
writeShellApplication {
  name = "make-checks";
  runtimeInputs = [
    nix-eval-jobs
    jq
  ];
  text = ''
    args=(
      "$@"
      --accept-flake-config
      --gc-roots-dir gcroot
      #--max-memory-size "3072" #allow users to set this themselves in extra params if needed
      --option allow-import-from-derivation false
      --force-recurse
      --flake .#checks
    )

    if [[ -n "''${GITHUB_STEP_SUMMARY-}" ]]; then
      log() {
        #Print to the Summary
        echo "$*" >> "$GITHUB_STEP_SUMMARY"
        #Print to the inline log
        echo "$*"
      }
    else
      log() {
        echo "$*"
      }
    fi

    echo "starting..."
    echo "Grab some Coffee, this will take a while..."

    retError=0

    for job in $(nix-eval-jobs "''${args[@]}" 2>/dev/null | jq -r '. | @base64'); do
      job=$(echo "$job" | base64 -d)
      attr=$(echo "$job" | jq -r .attr)
      error=$(echo "$job" | jq -r .error)
      if [[ $error != null ]]; then
        log "### ❌ $attr"
        log
        log "<details><summary>Eval error:</summary><pre>"
        log "$error"
        log "</pre></details>"
        retError=1
      else
       log "### ✅ $attr"
      fi
    done

    #TODO: should we remove gcroot?
    exit "$retError"
  '';
}
