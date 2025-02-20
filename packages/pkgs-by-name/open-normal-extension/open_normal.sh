#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Chrome browser extension action script to open a URL in normal browser
# Uses stdin and stdout for communicating with browser extension API
# First four bytes tell the size of payload, and rest is the payload,
# which is standard json data. Same format is used for input and output.

# Configuration file which contains the givc parameters
CFGF="/etc/open-normal-extension.cfg"

# Send browser extension API message. First send four bytes of the length of
# the payload and then the actual payload.
function Msg {
    local len b1 b2 b3 b4

    len="${#1}"
    b1="$(( len & 255 ))"
    b2="$(( (len >> 8) & 255 ))"
    b3="$(( (len >> 16) & 255 ))"
    b4="$(( (len >> 24) & 255 ))"
    printf "%b" "$(printf "\\\\x%02x\\\\x%02x\\\\x%02x\\\\x%02x" "$b1" "$b2" "$b3" "$b4")"
    printf "%s" "$1"
}

# Read the four bytes of length in the received API message
LEN="$(od -t u4 -A n -N 4 --endian=little)"

# 2022 HTTP standard recommends supporting URLs up to 8000 characters
# Generally URLs over 2000 characters will not work in the popular web browsers
# So 8k should be plenty for the time being
# If length is negative or zero or larger than 8k, then message is invalid
if [ -z "$LEN" ] || [ "$LEN" -le 0 ] || [ "$LEN" -gt 8192 ]; then
    Msg "{\"status\":\"Failed to read parameters from API\"}"
    exit 100
fi

# Read the json payload
LANG=C IFS= read -r -d '' -n "$LEN" JSON
# Remove json prefix
PFX="{\"URL\":\""
URL="${JSON##"$PFX"}"
# Remove json suffix
SFX="\"}"
URL="${URL%%"$SFX"}"

# Check that config file is readable
if [ -r "$CFGF" ]; then
    # Do not complain about not being able to follow non-constant source
    # shellcheck disable=SC1090
    . "$CFGF"
    # Sanity check settings
    if [ -z "$GIVC_PATH" ] || [ -z "$GIVC_OPTS" ] || [ ! -x "${GIVC_PATH}/bin/givc-cli" ]; then
        Msg "{\"status\":\"Invalid config in ${CFGF}\"}"
        exit 102
    else
        # Do not complain about double quotes, $GIVC_OPTS is purposefully unquoted here
        # shellcheck disable=SC2086
        "${GIVC_PATH}/bin/givc-cli" $GIVC_OPTS start app --vm chrome-vm google-chrome -- "${URL}" > /dev/null 2>&1
        RES=$?
        # Just return the exit value of givc-cli back to the browser
        Msg "{\"status\":\"${RES}\"}"
        exit "$RES"
    fi
else
    # Report error to the browser, config was nonexistent or unreadable
    Msg "{\"status\":\"Failed to read ${CFGF}\"}"
    exit 101
fi
