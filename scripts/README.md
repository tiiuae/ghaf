<!--
SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# NPM Dependencies Hash Automation

This directory contains the automation for updating `npmDepsHash` in `/docs/default.nix` when dependabot updates npm dependencies.

## Files

- `update-npm-deps-hash.sh`: Script that automatically updates the npmDepsHash
- `test-update-npm-deps-hash.sh`: Test script to validate the update functionality

## How it works

When dependabot creates a PR to update npm dependencies in `/docs/package.json` or `/docs/package-lock.json`, the GitHub workflow `.github/workflows/update-npm-deps-hash.yml` automatically:

1. Detects the dependabot PR
2. Runs the update script which:
   - Attempts to build the documentation with the current hash
   - Extracts the correct hash from the Nix build error message
   - Updates `/docs/default.nix` with the correct hash
   - Verifies the build works with the new hash
3. Commits and pushes the updated `default.nix` to the same PR

## Testing

Run the test script to validate functionality:

```bash
./scripts/test-update-npm-deps-hash.sh
```

This tests:

- Hash extraction from various Nix error message formats
- File structure validation
- Sed replacement functionality
- Script permissions

## Manual Usage

The script can also be run manually when needed:

```bash
./scripts/update-npm-deps-hash.sh
```

Note: This requires Nix to be installed and the script will attempt to build the documentation package to determine the correct hash.
