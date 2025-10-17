#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Script to transform an auditd .rules file for NixOS import

INPUT_DIR="$1"
OUTPUT_DIR="${2:-.}"
OUTPUT_DIR=${OUTPUT_DIR%/}
OUTPUT_DIR=$(realpath "$OUTPUT_DIR")

if [ -z "$INPUT_DIR" ]; then
  echo "Usage: $0 <path_to_rules_directory>"
  exit 1
fi

if [ ! -d "$INPUT_DIR" ]; then
  echo "Error: Input path '$INPUT_DIR' is not a directory."
  exit 1
fi

echo "Scanning directory: $INPUT_DIR for .rules files..."

find "$INPUT_DIR" -maxdepth 1 -type f -name "*.rules" -print0 | while IFS= read -r -d $'\0' current_input_file; do
  # Derive output filename: basename without .rules, then add .nix
  output_filename="$OUTPUT_DIR/$(basename "$current_input_file" .rules).nix"

  echo "Processing '$current_input_file' -> '$output_filename'..."

  # Create a unique temporary file for each processing iteration
  TMP_PROCESSED_CONTENT=$(mktemp)

  # Transformation Logic
  # 1. Delete lines containing "arch=b32"
  # 2. Enclose lines starting with "-a" (and "#-a") in double quotes
  # 3. Remove leading/trailing whitespace from all lines
  # 4. Filter out empty lines (which might result from deleting lines)
  sed -E '
    /^.*arch=b32.*$/d
    /^[[:space:]]*-/{
      s/^[[:space:]]*//
      s/^/"/
      s/$/"/
    }
    /^[[:space:]]*#-/{ # Match commented-out audit rules and format them
      s/^[[:space:]]*#/# "/
      s/$/"/
    }
    s/^[[:space:]]*//; s/[[:space:]]*$//
  ' "$current_input_file" | grep -v '^[[:space:]]*$' > "$TMP_PROCESSED_CONTENT"

  # Write the processed content to the output file
  (echo "["
  sed 's/^/  /' "$TMP_PROCESSED_CONTENT"
  echo "]") > "$output_filename"

  # Cleanup
  rm "$TMP_PROCESSED_CONTENT"

done

echo "All specified .rules files processed."
echo "Transformed .nix files are located in the current directory."
