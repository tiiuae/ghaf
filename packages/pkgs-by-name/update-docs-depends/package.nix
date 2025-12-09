# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellApplication,
  prefetch-npm-deps,
}:

writeShellApplication {
  name = "update-docs-deps";

  # Add / remove tools as needed
  runtimeInputs = [
    prefetch-npm-deps
  ];

  text = ''
    set -euo pipefail

    # Parse command-line arguments
    UPGRADE=false
    while [[ $# -gt 0 ]]; do
      case $1 in
        --upgrade)
          UPGRADE=true
          shift
          ;;
        -h|--help)
          echo "Usage: update-docs-deps [--upgrade]"
          echo ""
          echo "Options:"
          echo "  --upgrade    Upgrade dependencies to latest versions (npm upgrade)"
          echo "  --help       Show this help message"
          echo ""
          echo "By default, runs 'npm update' to update within semver constraints."
          echo "With --upgrade, runs 'npm upgrade' to get latest versions."
          exit 0
          ;;
        *)
          echo "Error: Unknown option: $1" >&2
          echo "Use --help for usage information." >&2
          exit 1
          ;;
      esac
    done

    if [ "$UPGRADE" = true ]; then
      echo "[update-docs-deps] Starting (upgrade mode)…"
    else
      echo "[update-docs-deps] Starting (update mode)…"
    fi

    # Find repo root (directory containing .git)
    if ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
      cd "$ROOT"
    else
      echo "Error: Not inside a git repository." >&2
      exit 1
    fi

    DOCS_DIR="docs"

    if [ ! -d "$DOCS_DIR" ]; then
      echo "Error: $DOCS_DIR directory not found at $ROOT" >&2
      exit 1
    fi

    if [ ! -f "$DOCS_DIR/package.json" ]; then
      echo "Error: $DOCS_DIR/package.json not found." >&2
      exit 1
    fi

    # Ensure a clean working tree before starting (besides untracked files)
    if ! git diff --quiet || ! git diff --cached --quiet; then
      echo "Error: Working tree has unstaged or staged changes. Commit/stash them first." >&2
      exit 1
    fi

    pushd "$DOCS_DIR" >/dev/null

    # Prefer using existing lock file; do not delete it
    if [ -f package-lock.json ]; then
      echo "[update-docs-deps] Using existing package-lock.json"
    fi

    if [ "$UPGRADE" = true ]; then
      echo "[update-docs-deps] Running npm upgrade in $DOCS_DIR (latest versions)"
      # npm upgrade requires npm-check-updates or manual package.json edits
      # We'll use npx to run npm-check-updates to upgrade package.json, then npm install
      if command -v npx &> /dev/null; then
        npx --yes npm-check-updates -u
        npm install
      else
        echo "Error: npx not found. Cannot run upgrade mode." >&2
        exit 1
      fi
    else
      echo "[update-docs-deps] Running npm update in $DOCS_DIR (within semver constraints)"
      npm update
    fi

    WANTED_HASH=$(prefetch-npm-deps ./package-lock.json)
    if [ -z "$WANTED_HASH" ]; then
      echo "Error: Hash could not be created"
      exit 1
    fi

    echo "[update-docs-deps] New npm deps hash: $WANTED_HASH"

    # now update the vendor hash in the default.nix file
    sed -i -E "s|npmDepsHash[[:space:]]*=[[:space:]]*\"[^\"]*\"|npmDepsHash = \"$WANTED_HASH\"|" default.nix

    popd >/dev/null

    echo "[update-docs-deps] Verifying doc build (nix build .#doc)"
    if nix build .#doc; then
      echo "[update-docs-deps] Build succeeded."
    else
      echo "Error: nix build .#doc failed." >&2
      exit 1
    fi

    # Detect if anything actually changed
    if git diff --quiet && git diff --cached --quiet; then
      echo "[update-docs-deps] No changes produced; nothing to stage."
      exit 0
    fi

    # Create a unique branch
    TS="$(date -u +%Y%m%d-%H%M%S)"
    if [ "$UPGRADE" = true ]; then
      BRANCH="upgrade-docs-deps-$TS"
    else
      BRANCH="update-docs-deps-$TS"
    fi

    # Detect default remote and branch
    REMOTE="''${REMOTE:-origin}"
    DEFAULT_BRANCH_REF="$(git symbolic-ref "refs/remotes/$REMOTE/HEAD" 2>/dev/null || true)"
    if [ -z "$DEFAULT_BRANCH_REF" ]; then
      echo "Error: Could not determine default branch for remote '$REMOTE'." >&2
      exit 1
    fi
    DEFAULT_BRANCH="''${DEFAULT_BRANCH_REF##*/}"

    echo "[update-docs-deps] Creating branch: $BRANCH from $REMOTE/$DEFAULT_BRANCH"
    git checkout -b "$BRANCH" "$REMOTE/$DEFAULT_BRANCH"


    echo "[update-docs-deps] Staging relevant changes"
    # Be explicit; adjust patterns if your flake layout differs
    git add \
      "$DOCS_DIR/default.nix" \
      "$DOCS_DIR/package.json" \
      "$DOCS_DIR/package-lock.json"

    if git diff --cached --quiet; then
      echo "Error: After staging, still no changes. Exiting." >&2
      exit 1
    fi

    echo
    echo "[update-docs-deps] Changes staged on branch $BRANCH."
    echo "Next steps:"
    echo "  1. Review with: git diff --cached"
    if [ "$UPGRADE" = true ]; then
      echo "  2. Commit: git commit -sm 'docs: upgrade npm dependencies to latest versions'"
    else
      echo "  2. Commit: git commit -sm 'docs: update npm dependencies & hash'"
    fi
    echo "  3. Push:   git push -u origin $BRANCH"
    echo "  4. Open a PR."
    echo
    echo "[update-docs-deps] Done."
  '';
}
