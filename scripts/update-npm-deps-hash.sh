#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

echo "Starting npmDepsHash update process..."

DOCS_DIR="docs"
DEFAULT_NIX="$DOCS_DIR/default.nix"

# Check if we're in the right directory
if [[ ! -f "$DEFAULT_NIX" ]]; then
    echo "Error: $DEFAULT_NIX not found. Make sure you're running this from the repository root."
    exit 1
fi

# Check if package.json or package-lock.json have changed
# In CI context, we can rely on the workflow path filter, so skip this check
if [[ "${CI:-}" != "true" ]]; then
    if ! git diff --name-only HEAD~1 | grep -q "^docs/package"; then
        echo "No changes detected in docs/package.json or docs/package-lock.json. Exiting."
        exit 0
    fi
fi

echo "Detected changes in npm dependencies. Updating npmDepsHash..."

# Function to extract hash from nix build error
extract_hash_from_error() {
    local error_output="$1"
    # Look for the "got:" line and extract the hash from it
    local got_hash=$(echo "$error_output" | grep -A1 "got:" | grep -oE 'sha256-[A-Za-z0-9+/]+=*' | head -1)
    
    if [[ -n "$got_hash" ]]; then
        echo "$got_hash"
        return 0
    fi
    
    # Alternative: look for "actual:" or similar patterns
    local actual_hash=$(echo "$error_output" | grep -i "actual:" | grep -oE 'sha256-[A-Za-z0-9+/]+=*' | head -1)
    
    if [[ -n "$actual_hash" ]]; then
        echo "$actual_hash"
        return 0
    fi
    
    # Fallback: look for any hash that appears after "expected" or "got"
    local fallback_hash=$(echo "$error_output" | grep -oE 'sha256-[A-Za-z0-9+/]+=*' | tail -1)
    
    if [[ -n "$fallback_hash" ]]; then
        echo "$fallback_hash"
        return 0
    fi
    
    echo ""
    return 1
}

# Try to build the documentation to get the expected hash
echo "Attempting to build documentation to determine correct hash..."

# Capture both stdout and stderr
build_output=$(nix build .#doc 2>&1) || build_exit_code=$?

if [[ ${build_exit_code:-0} -eq 0 ]]; then
    echo "Build succeeded unexpectedly. The hash may already be correct."
    exit 0
fi

echo "Build failed as expected. Extracting correct hash from error message..."

# Extract the expected hash from the error message
expected_hash=$(extract_hash_from_error "$build_output")

if [[ -z "$expected_hash" ]]; then
    echo "Error: Could not extract expected hash from build output."
    echo "Build output:"
    echo "$build_output"
    exit 1
fi

echo "Expected hash: $expected_hash"

# Get current hash from default.nix
current_hash=$(grep -oE 'npmDepsHash = "[^"]*"' "$DEFAULT_NIX" | sed 's/npmDepsHash = "\(.*\)"/\1/')

if [[ -z "$current_hash" ]]; then
    echo "Error: Could not find current npmDepsHash in $DEFAULT_NIX"
    exit 1
fi

echo "Current hash: $current_hash"

if [[ "$current_hash" == "$expected_hash" ]]; then
    echo "Hash is already correct. No update needed."
    exit 0
fi

# Update the hash in default.nix
echo "Updating npmDepsHash in $DEFAULT_NIX..."

# Use sed to replace the hash
sed -i "s|npmDepsHash = \"$current_hash\"|npmDepsHash = \"$expected_hash\"|" "$DEFAULT_NIX"

# Verify the change was made
new_hash=$(grep -oE 'npmDepsHash = "[^"]*"' "$DEFAULT_NIX" | sed 's/npmDepsHash = "\(.*\)"/\1/')

if [[ "$new_hash" != "$expected_hash" ]]; then
    echo "Error: Failed to update hash in $DEFAULT_NIX"
    exit 1
fi

echo "Successfully updated npmDepsHash from $current_hash to $expected_hash"

# Verify the build works with the new hash
echo "Verifying build with updated hash..."
if nix build .#doc; then
    echo "Build verification successful!"
else
    echo "Error: Build still fails with updated hash. This may indicate a deeper issue."
    exit 1
fi

echo "npmDepsHash update completed successfully."