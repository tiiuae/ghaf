# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellApplication,
  libnotify,
  ollama,
  alpaca,
  ghaf-artwork ? null,
  curl,
}:
writeShellApplication {
  name = "falcon-launcher";
  bashOptions = [ "errexit" ];
  runtimeInputs = [
    libnotify
    ollama
    alpaca
    curl
  ];
  text = ''
    DOWNLOAD_FLAG="/tmp/falcon-download"
    LLM_NAME="falcon3:10b"
    LLM_FRIENDLY_NAME="Falcon 3"
    FALCON_AI_ICON_PATH=${
      if ghaf-artwork != null then "${ghaf-artwork}/icons/falcon-icon.svg" else "falcon-icon"
    }
    NOTIFICATION_ID=
    TMP_LOG=

    cleanup() {
        echo 0 > "$DOWNLOAD_FLAG"
        rm "$TMP_LOG" 2>/dev/null
    }

    trap cleanup EXIT

    # If Falcon2 model is already installed, launch Alpaca
    if ollama show "$LLM_NAME" &>/dev/null; then
        echo "$LLM_NAME is already installed"
        alpaca
        exit 0
    fi

    # If download is already ongoing, wait for it to finish
    if [[ -f "$DOWNLOAD_FLAG" && "$(cat "$DOWNLOAD_FLAG")" == "1" ]]; then
        echo "$LLM_NAME is currently being installed..."
        exit 0
    else
        # Start new download
        echo 1 > "$DOWNLOAD_FLAG"
        NOTIFICATION_ID=$(notify-send -a "Falcon AI" -h "string:image-path:$FALCON_AI_ICON_PATH" -h byte:urgency:1 -t 5000 "Downloading $LLM_FRIENDLY_NAME" "The app will open once the download is complete" --print-id)
    fi

    # Temp file to capture full Ollama pull output
    TMP_LOG=$(mktemp)

    # Check for connectivity to Ollama's model registry
    if ! curl --connect-timeout 3 -I https://ollama.com 2>&1; then
      notify-send --replace-id="$NOTIFICATION_ID" \
          -h byte:urgency:1 \
          -t 5000 \
          -a "Falcon AI" \
          -h "string:image-path:$FALCON_AI_ICON_PATH" \
          "No Internet Connection" "Cannot download $LLM_FRIENDLY_NAME\nCheck your connection and try again"
      exit 1
    fi

    echo "Downloading $LLM_FRIENDLY_NAME ..."
    last_percent=""
    ollama pull "$LLM_NAME" 2>&1 | tee "$TMP_LOG" | while read -r line; do
        if [[ $line =~ ([0-9]{1,3})% ]]; then
            percent="''${BASH_REMATCH[1]}"
            # Skip updating same percentage
            [[ "$percent" == "$last_percent" ]] && continue
            last_percent="$percent"
            NOTIFICATION_ID=$(notify-send --print-id --replace-id="$NOTIFICATION_ID" \
                -h byte:urgency:2 \
                -t 120000 \
                -h "string:image-path:$FALCON_AI_ICON_PATH" \
                -a "Falcon AI" \
                "Downloading $LLM_FRIENDLY_NAME  $percent%" \
                "The app will open once the download is complete")
        fi
    done

    status=''${PIPESTATUS[0]}

    # Final notification
    if [[ $status -eq 0 ]]; then
        echo "Download completed successfully"
        notify-send --replace-id="$NOTIFICATION_ID" \
            -h byte:urgency:0 \
            -t 3000 \
            -a "Falcon AI" \
            -h "string:image-path:$FALCON_AI_ICON_PATH" \
            "Download complete" \
            "The application will now open"
        alpaca
        exit 0
    else
        echo "Download failed with status $status"
        error_msg=$(tail -n 1 "$TMP_LOG")
        notify-send --replace-id="$NOTIFICATION_ID" \
            -h byte:urgency:2 \
            -t 5000 \
            -a "Falcon AI" \
            -h "string:image-path:$FALCON_AI_ICON_PATH" \
            "Failed to download $LLM_FRIENDLY_NAME" \
            "Error occurred:\n''${error_msg}"
    fi
  '';

  meta = {
    description = "Script to setup and/or launch the Falcon LLM chat";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
