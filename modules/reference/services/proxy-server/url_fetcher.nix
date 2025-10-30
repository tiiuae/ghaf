# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellApplication,
  pkgs,
  ...
}:
let
  logTag = "url-fetcher";
in
writeShellApplication {
  name = "url-fetcher";
  runtimeInputs = [
    pkgs.inetutils
    pkgs.curl
    pkgs.jq
    pkgs.gawk
  ];
  text = ''
      # Default values for variables
    url=""
    url_folder=""
    allowListPath=""
    # Function to write to the allow list
    write_to_allow_list() {
        local processedUrls="$1"
        local allowListPath="$2"

        {
            # Ensure the "allow" prefix is written
            printf "allow * * " || { logger -t ${logTag} "Failed to print prefix"; return 1; }
            echo "$processedUrls" || { logger -t ${logTag} "Failed to echo processed URLs"; return 1; }
        } > "$allowListPath" || { logger -t ${logTag} "Failed to write to $allowListPath"; return 2; }

        return 0  # Indicate success
    }

    # Function to fetch and process URLs from a JSON file
    fetch_and_process_url() {
        local file_url="$1"

        # Fetch and parse the JSON
        if json_content=$(curl -s --retry 5 --retry-delay 10 --retry-connrefused "$file_url"); then
            echo "$json_content" | jq -r '.[]? | select(.category == "Optimize" or .category == "Allow" or .category == "Default") | .urls[]?' | sort | uniq
        else
            logger -t ${logTag} "Failed to fetch or parse JSON from $file_url"
            return 1
        fi
    }

    # Parse command line arguments
    while getopts "u:f:p:" opt; do
        case $opt in
            u) url="$OPTARG" ;;         # Single JSON file URL to fetch
            f) url_folder="$OPTARG" ;;  # Folder API URL containing JSON files
            p) allowListPath="$OPTARG" ;; # Path to the allow list file
            \?) echo "Usage: $0 -u <url> | -f <folder_url> -p <allowListPath>"
                exit 1 ;;
        esac
    done

    # Validate input parameters
    if [[ -z "$allowListPath" ]]; then
        echo "Error: Allow List Path (-p) must be provided."
        echo "Usage: $0 -u <url> | -f <folder_url> -p <allowListPath>"
        exit 1
    fi

    if [[ -n "$url" && -n "$url_folder" ]]; then
        echo "Error: Only one of -u or -f should be provided, not both."
        exit 1
    elif [[ -z "$url" && -z "$url_folder" ]]; then
        echo "Error: One of -u or -f must be provided."
        exit 1
    fi

    # Check if the device is connected to the internet
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        logger -t ${logTag} "No internet connection. URLs not fetched."
        exit 3
    fi

    # Process a single URL (-u option)
    all_urls=""
    if [[ -n "$url" ]]; then
        logger -t ${logTag} "Fetching URLs from $url"

        # Fetch and process the single JSON file
        fetched_urls=$(fetch_and_process_url "$url")
        if [[ -z "$fetched_urls" ]]; then
            logger -t ${logTag} "No valid URLs found in the file $url"
            exit 4
        fi
        all_urls="$fetched_urls"
    fi

    # Process a folder of JSON files (-f option)
    if [[ -n "$url_folder" ]]; then
        logger -t ${logTag} "Fetching JSON files from folder $url_folder"

        # Use the folder URL directly as the API endpoint
        folder_api_url="$url_folder"

        # Fetch the folder contents from the API
        folder_response=$(curl -s -H "Accept: application/vnd.github.v3+json" "$folder_api_url")

        # Extract JSON file URLs
        file_urls=$(echo "$folder_response" | jq -r '.[] | select(.name | endswith(".json")) | .download_url')

        if [[ -z "$file_urls" ]]; then
            logger -t ${logTag} "No JSON files found in folder $folder_api_url"
            exit 4
        fi

        # Process each JSON file URL
        for file_url in $file_urls; do
            fetched_urls=$(fetch_and_process_url "$file_url")
            all_urls+="$fetched_urls"$'\n'
        done
    fi

    # Deduplicate and format URLs
    all_urls=$(echo "$all_urls" | sort | uniq | tr '\n' ',')  # Sort, deduplicate, join with commas
    all_urls=$(echo "$all_urls" | awk '{sub(/^,/, ""); print}')
    all_urls=$(echo "$all_urls" | awk '{gsub(/^,|,$/, ""); print}')

    # Write to the allow list
    if write_to_allow_list "$all_urls" "$allowListPath"; then
        logger -t ${logTag} "URLs fetched and saved to $allowListPath successfully"
        exit 0  # Success
    else
        logger -t ${logTag} "Failed to save URLs to allow list"
        exit 2
    fi
  '';
  meta = {
    description = "
          The application is a shell script designed to fetch a list of URLs
      from a specified endpoint and save them to an allow list file. The script includes error
      handling and retry logic to ensure robustness in various network conditions.
    ";
  };
}
