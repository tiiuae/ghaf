#!/usr/bin/env bash
    
# SPDX-FileCopyrightText: 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
        
################################################################################
    
# This script is a helper to evaluate flake outputs in github actions.
    
set -e # exit immediately if a command fails
set -E # exit immediately if a command fails (subshells)
set -u # treat unset variables as an error and exit
set -o pipefail # exit if any pipeline command fails

if [ "$#" != 2 ]; then
  echo "Usage: $0 prefix target" >&2
  exit 1
fi

PREFIX="$1"
TARGET="$2"
CACHIX_REPO="${CACHIX_REPO:-ghaf-dev}"
PIN_NAME="${PREFIX}-%{TARGET}"

path=$(nixos-rebuild build --flake ".#${TARGET}" --no-out-link)
cachix push "${CACHIX_REPO}" "${path}"
cachix pin "${CACHIX_REPO}" "${PIN_NAME}" "${path}"
