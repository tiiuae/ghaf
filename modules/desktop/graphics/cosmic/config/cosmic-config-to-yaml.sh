#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# This script generates a YAML file from the Cosmic config file tree in the specified directory

if [ -z "$1" ]; then
    echo "Usage: $0 <source_directory>"
    exit 1
fi

OUTPUT_FILE="cosmic.config.yaml"
BASE_DIR="$1"

echo "" > "$OUTPUT_FILE"

# Iterate over top-level directories
for dir in "$BASE_DIR"/*/; do
    # Get the top-level directory name
    dir_name=$(basename "$dir")
    echo "$dir_name:" >> "$OUTPUT_FILE"
    
    # Iterate over files in the v1 subdirectory
    for file in "$dir"v1/*; do
        if [[ -f "$file" ]]; then
            key=$(basename "$file")
            value=$(cat "$file")
            
            # Format the value correctly
            if [[ "$value" == *$'\n'* ]]; then
                echo "  $key: |" >> "$OUTPUT_FILE"
                while IFS= read -r line; do
                    echo "    $line" >> "$OUTPUT_FILE"
                done <<< "$value"
            else
                echo "  $key: $value" >> "$OUTPUT_FILE"
            fi
        fi
    done
    echo "" >> "$OUTPUT_FILE"
done

echo "Cosmic config YAML generated at $OUTPUT_FILE"
