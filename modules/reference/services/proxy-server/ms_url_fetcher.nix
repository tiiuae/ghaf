# Copyright 2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellApplication,
  lib,
  pkgs,
  allowListPath,
  ...
}:
let
  url = "https://endpoints.office.com/endpoints/worldwide?clientrequestid=b10c5ed1-bad1-445f-b386-b919946339a7";
  logTag = "ms-url-fetcher";
in
writeShellApplication {
  name = "ms-url-fetch";
  runtimeInputs = [
    pkgs.inetutils
    pkgs.curl
    pkgs.jq
  ];
  text = ''
    # Function to write to the allow list
     write_to_allow_list() {
       
         local processedUrls="$1"
         local allowListPath="$2"
      
         {
             printf "allow * * " || { logger -t ms-url-fetcher "Failed to print prefix"; return 1; }
             echo "$processedUrls" || { logger -t ms-url-fetcher "Failed to echo processed URLs"; return 1; }
         } > "$allowListPath" || { logger -t ms-url-fetcher "Failed to write to $allowListPath"; return 2; }
         return 0  # Indicate success
     }
        # Check if the device is connected to the internet.
         if ping -c 1 8.8.8.8 &> /dev/null; then  
           logger -t ${logTag} "Fetching the Microsoft URLs from ${url}"

           # Fetch the JSON file using curl with retry logic
           if curl_output=$(curl -s --retry 5 --retry-delay 10 --retry-connrefused "${url}"); then
            msurl_output=$(echo "$curl_output" | jq -r '.[]? | select(.category == "Optimize" or .category == "Allow" or .category == "Default") | .urls[]?' | sort | uniq)
           # Check if msurl_output is empty
         if [ -z "$msurl_output" ]; then
           logger -t ${logTag} "No valid URLs found in the fetched data."
           exit 4  # No URLs found error
         fi

         # Convert the list of URLs into a comma-separated format and save to allowListPath
         processedUrls=$(echo "$msurl_output" | tr '\n' ',' | sed 's/,$//');
         
           
       
             # Add the prefix once and save to allowListPath
            if write_to_allow_list "$processedUrls" "${allowListPath}"; then
               logger -t ${logTag} "Microsoft URLs fetched and saved to ${allowListPath} successfully"
               exit 0  # Success exit code
             else
               logger -t ${logTag} "Failed to process Microsoft URLs with jq"
               exit 2  # JQ processing error
             fi
           else
             logger -t ${logTag} "Failed to fetch Microsoft URLs after multiple attempts"
             exit 1  # Curl fetching error
           fi
         else
           logger -t ${logTag} "No internet connection. Microsoft URLs not fetched."
           exit 3  # No internet connection error
         fi
  '';
  meta = with lib; {
    description = "
          The application is a shell script designed to fetch a list of Microsoft URLs
      from a specified endpoint and save them to an allow list file. The script includes error 
      handling and retry logic to ensure robustness in various network conditions.
    ";
  };
}
