# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
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

    echo "[update-docs-deps] Starting…"

    # Find repo root (directory containing .git)
    if ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
      cd "$ROOT"
    else
      echo "Error: Not inside a git repository." >&2
      exit 1
    fi

    DOCS_DIR="docs"
    UPDATE_HASH_SCRIPT="scripts/update-npm-deps-hash.sh"

    if [ ! -d "$DOCS_DIR" ]; then
      echo "Error: $DOCS_DIR directory not found at $ROOT" >&2
      exit 1
    fi

    if [ ! -f "$DOCS_DIR/package.json" ]; then
      echo "Error: $DOCS_DIR/package.json not found." >&2
      exit 1
    fi

    if [ ! -x "$UPDATE_HASH_SCRIPT" ]; then
      if [ -f "$UPDATE_HASH_SCRIPT" ]; then
        echo "Info: $UPDATE_HASH_SCRIPT not executable, attempting to run with bash."
      else
        echo "Error: Hash update script $UPDATE_HASH_SCRIPT not found." >&2
        exit 1
      fi
    fi

    # Ensure a clean working tree before starting (besides untracked files)
    if ! git diff --quiet || ! git diff --cached --quiet; then
      echo "Error: Working tree has unstaged or staged changes. Commit/stash them first." >&2
      exit 1
    fi

    echo "[update-docs-deps] Running npm update in $DOCS_DIR"
    pushd "$DOCS_DIR" >/dev/null

    # Prefer using existing lock file; do not delete it
    if [ -f package-lock.json ]; then
      echo "[update-docs-deps] Using existing package-lock.json"
    fi

    npm update

    # Optionally re-install to ensure lock integrity (uncomment if desired)
    # npm install --package-lock-only

    popd >/dev/null

    echo "[update-docs-deps] Updating npmDepsHash via $UPDATE_HASH_SCRIPT"
    if [ -x "$UPDATE_HASH_SCRIPT" ]; then
      "$UPDATE_HASH_SCRIPT"
    else
      bash "$UPDATE_HASH_SCRIPT"
    fi

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
    BRANCH="update-docs-deps-$TS"

    echo "[update-docs-deps] Creating branch: $BRANCH"
    git switch -c "$BRANCH"

    echo "[update-docs-deps] Staging relevant changes"
    # Be explicit; adjust patterns if your flake layout differs
    git add \
      "$DOCS_DIR/package.json" \
      "$DOCS_DIR/package-lock.json" 2>/dev/null || true

    # Common files affected by hash updates
    if [ -f flake.nix ]; then git add flake.nix; fi
    if [ -f flake.lock ]; then git add flake.lock; fi

    # Add any other known generated hash / pin files if present
    # git add path/to/generated-npm-hash.nix 2>/dev/null || true

    # Fallback: if nothing staged yet but there ARE diffs, stage all modified tracked files
    if git diff --cached --quiet; then
      echo "[update-docs-deps] No files explicitly matched; staging all modified tracked files."
      git add -u
    fi

    if git diff --cached --quiet; then
      echo "Error: After staging, still no changes. Exiting." >&2
      exit 1
    fi

    echo
    echo "[update-docs-deps] Changes staged on branch $BRANCH."
    echo "Next steps:"
    echo "  1. Review with: git diff --cached"
    echo "  2. Commit: git commit -m 'docs: update npm dependencies & hash'"
    echo "  3. Push:   git push -u origin $BRANCH"
    echo "  4. Open a PR."
    echo
    echo "[update-docs-deps] Done."
  '';
}
