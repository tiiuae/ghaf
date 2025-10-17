#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# Assert root
[[ "$EUID" -ne 0 ]] && echo "Please run as root." && exit 1

# Usage
if [[ "$#" -lt 5 || "$#" -gt 7 ]]; then
    echo "Usage: $0 <admin service ip> <admin service port> <vm-name> <unit-name> <timeout in seconds> [<status>] [<sub_status>]"
    exit 1
fi

# Check if key/certificates exist
[[ ! -f /etc/givc/ca-cert.pem ]] && echo "CA certificate not found." && exit 1
[[ ! -f /etc/givc/cert.pem ]] && echo "Client certificate not found." && exit 1
[[ ! -f /etc/givc/key.pem ]] && echo "Client key not found." && exit 1

# Function to fetch the unit status
ADDR="$1:$2"
VM="$3"
UNIT="$4"
args=(
    "-cacert" "/etc/givc/ca-cert.pem"
    "-cert" "/etc/givc/cert.pem"
    "-key" "/etc/givc/key.pem"
    "-d" "{\"VmName\":\"$VM\",\"UnitName\":\"$UNIT\"}"
    "$ADDR"
    "admin.AdminService.GetUnitStatus"
)
TIMEOUT="$5"

# Optional inputs for expected unit status
EXPECTED_STATUS=""
if [ "$#" -ge 6 ]; then
    EXPECTED_STATUS="$6"
fi
SUB_STATUS=""
if [ "$#" -eq 7 ]; then
    SUB_STATUS="$7"
fi

# Wait until the unit is running
echo "Waiting for unit '$UNIT' in VM '$VM' ..."
SECONDS=0
while [ $SECONDS -lt "$TIMEOUT" ]; do
    if status_response="$(grpcurl "${args[@]}" 2>/dev/null)"; then
        active_status=$(echo "$status_response" | jq -rj '.ActiveState')
        sub_status=$(echo "$status_response" | jq -rj '.SubState')
        if [[ -n "$EXPECTED_STATUS" ]]; then
            if [[ -z "$SUB_STATUS" ]]; then
                # No sub-state eval
                [[ "$active_status" == "$EXPECTED_STATUS" ]] && exit 0
            else
                # Custom status and sub status
                [[ "$active_status" == "$EXPECTED_STATUS" && "$sub_status" == "$SUB_STATUS" ]] && exit 0
            fi
        else
            # Default to generic 'active' service eval
            [[ "$active_status" == "active" && ("$sub_status" == "active" || "$sub_status" == "running" || "$sub_status" == "exited") ]] && exit 0
        fi
    else
        echo "Waiting to get status for unit '$UNIT' in VM '$VM' ..."
    fi
    sleep 0.5
done
echo "Timeout reached: Unit '$UNIT' in VM '$VM' did not reach the desired state within $TIMEOUT seconds. Exit gracefully."
