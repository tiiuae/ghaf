<!--
SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Testing the npmDepsHash Automation

## How to Test the Implementation

### 1. Automated Testing

Run the included test suite:

```bash
./scripts/test-update-npm-deps-hash.sh
```

This validates:

- Hash extraction from Nix error messages
- File manipulation operations
- Workflow YAML syntax
- Script permissions and structure

### 2. Manual Testing (with Nix)

If you have Nix installed, you can test the actual update process:

```bash
# Make a backup of the current default.nix
cp docs/default.nix docs/default.nix.backup

# Intentionally break the hash to trigger an update
sed -i 's/npmDepsHash = ".*"/npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="/' docs/default.nix

# Run the update script
./scripts/update-npm-deps-hash.sh

# The script should detect the wrong hash, extract the correct one from the build error, and update the file

# Restore the backup
cp docs/default.nix.backup docs/default.nix
rm docs/default.nix.backup
```

### 3. Integration Testing with Dependabot

To test the full workflow integration:

1. Create a test branch
2. Modify `docs/package.json` to bump a dependency version
3. Create a PR with the title format that dependabot uses: `build(deps): bump [package] from [old] to [new]`
4. Ensure the PR author is `dependabot[bot]` (or simulate this in a test environment)
5. The workflow should trigger and automatically update the npmDepsHash

### 4. Workflow Trigger Validation

The workflow will only run when:

- Event type is `pull_request` with types `opened` or `synchronize`
- Files changed include `docs/package.json` or `docs/package-lock.json`
- PR author is `dependabot[bot]`
- PR is from the same repository (not a fork)

### Expected Behavior

When dependabot updates npm dependencies:

1. A new PR is created with updated package.json/package-lock.json
2. The workflow detects the PR and triggers
3. The script runs a Nix build which fails due to hash mismatch
4. The correct hash is extracted from the error message
5. `docs/default.nix` is updated with the correct hash
6. A verification build confirms the fix works
7. Changes are committed and pushed to the same PR

### Troubleshooting

- Check GitHub Actions logs for detailed output
- Ensure Nix is properly installed in the CI environment
- Verify permissions are correctly set for the workflow
- Check that the npmDepsHash pattern in default.nix matches the regex

### Security Considerations

- The workflow only runs on dependabot PRs from the same repository
- No external code execution - only Nix builds and hash extraction
- Uses standard GitHub Actions security practices
- Minimal required permissions (contents: write, pull-requests: write)
