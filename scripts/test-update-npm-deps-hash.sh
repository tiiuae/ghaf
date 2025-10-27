#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# Test script for update-npm-deps-hash.sh
set -euo pipefail

echo "Testing update-npm-deps-hash.sh functionality..."

# Extract the hash extraction function for testing
extract_hash_from_error() {
    local error_output="$1"
    # Look for the "got:" line and extract the hash from it
    local got_hash
    got_hash=$(echo "$error_output" | grep -A1 "got:" | grep -oE 'sha256-[A-Za-z0-9+/]+=*' | head -1)

    if [[ -n "$got_hash" ]]; then
        echo "$got_hash"
        return 0
    fi

    # Alternative: look for "actual:" or similar patterns
    local actual_hash
    actual_hash=$(echo "$error_output" | grep -i "actual:" | grep -oE 'sha256-[A-Za-z0-9+/]+=*' | head -1)

    if [[ -n "$actual_hash" ]]; then
        echo "$actual_hash"
        return 0
    fi

    # Fallback: look for any hash that appears after "expected" or "got"
    local fallback_hash
    fallback_hash=$(echo "$error_output" | grep -oE 'sha256-[A-Za-z0-9+/]+=*' | tail -1)

    if [[ -n "$fallback_hash" ]]; then
        echo "$fallback_hash"
        return 0
    fi

    echo ""
    return 1
}

# Test 1: Hash extraction function
test_hash_extraction() {
    echo "Test 1: Hash extraction function"

    # Test with typical Nix error output
    error_output='error: hash mismatch in fixed-output derivation /nix/store/abc123-source
  specified: sha256-oldHashValue123+/=
  got:        sha256-ckKaqnh2zAe34Hi+fpmf2NqoIB8KyEVMrvv3jdnkp4U='

    expected_hash=$(extract_hash_from_error "$error_output")

    if [[ "$expected_hash" == "sha256-ckKaqnh2zAe34Hi+fpmf2NqoIB8KyEVMrvv3jdnkp4U=" ]]; then
        echo "✓ Hash extraction test passed"
    else
        echo "✗ Hash extraction test failed. Got: '$expected_hash'"
        return 1
    fi

    # Test with alternative format
    error_output2='error: hash mismatch
  actual:   sha256-AlternativeHash456+/=
  expected: sha256-oldValue789+/='

    expected_hash2=$(extract_hash_from_error "$error_output2")

    if [[ "$expected_hash2" == "sha256-AlternativeHash456+/=" ]]; then
        echo "✓ Alternative hash format test passed"
    else
        echo "✗ Alternative hash format test failed. Got: '$expected_hash2'"
        return 1
    fi
}

# Test 2: Sed replacement
test_sed_replacement() {
    echo "Test 2: Sed replacement functionality"

    # Create a temporary test file
    test_file="/tmp/test_default.nix"
    cp docs/default.nix "$test_file"

    # Extract current hash
    current_hash=$(grep -oE 'npmDepsHash = "[^"]*"' "$test_file" | sed 's/npmDepsHash = "\(.*\)"/\1/')

    if [[ -z "$current_hash" ]]; then
        echo "✗ Could not extract current hash from test file"
        rm "$test_file"
        return 1
    fi

    # Test hash replacement
    new_hash="sha256-TestHashReplacement123+/="
    sed -i "s|npmDepsHash = \"$current_hash\"|npmDepsHash = \"$new_hash\"|" "$test_file"

    # Verify the change
    updated_hash=$(grep -oE 'npmDepsHash = "[^"]*"' "$test_file" | sed 's/npmDepsHash = "\(.*\)"/\1/')

    if [[ "$updated_hash" == "$new_hash" ]]; then
        echo "✓ Sed replacement test passed"
    else
        echo "✗ Sed replacement test failed. Expected: $new_hash, Got: $updated_hash"
        rm "$test_file"
        return 1
    fi

    rm "$test_file"
}

# Test 3: File structure validation
test_file_structure() {
    echo "Test 3: File structure validation"

    if [[ ! -f "docs/default.nix" ]]; then
        echo "✗ docs/default.nix not found"
        return 1
    fi

    if [[ ! -f "docs/package.json" ]]; then
        echo "✗ docs/package.json not found"
        return 1
    fi

    if [[ ! -f "docs/package-lock.json" ]]; then
        echo "✗ docs/package-lock.json not found"
        return 1
    fi

    # Check if npmDepsHash exists in default.nix
    if ! grep -q "npmDepsHash" docs/default.nix; then
        echo "✗ npmDepsHash not found in docs/default.nix"
        return 1
    fi

    echo "✓ File structure validation passed"
}

# Test 4: Script exists and is executable
test_script_exists() {
    echo "Test 4: Script validation"

    if [[ ! -f "scripts/update-npm-deps-hash.sh" ]]; then
        echo "✗ scripts/update-npm-deps-hash.sh not found"
        return 1
    fi

    if [[ ! -x "scripts/update-npm-deps-hash.sh" ]]; then
        echo "✗ scripts/update-npm-deps-hash.sh is not executable"
        return 1
    fi

    echo "✓ Script validation passed"
}

# Run tests
echo "Running tests..."
test_file_structure
test_script_exists
test_hash_extraction
test_sed_replacement

echo ""
echo "All tests passed! ✓"
