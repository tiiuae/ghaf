#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# Assert root
[[ $EUID -ne 0 ]] && echo "Please run as root." && exit 1

GIVC_ARGS="@GIVC_ARGS@"
if [[ -z ${GIVC_ARGS} ]]; then
  GIVC_ARGS="${GIVC_OPTS:-}"
fi

if [[ -z ${GIVC_ARGS} ]]; then
  # Check if key/certificates exist (only for fallback configuration)
  [[ ! -f /etc/givc/ca-cert.pem ]] && echo "CA certificate not found." && exit 1
  [[ ! -f /etc/givc/cert.pem ]] && echo "Client certificate not found." && exit 1
  [[ ! -f /etc/givc/key.pem ]] && echo "Client key not found." && exit 1

  args=(
    "--addr" "192.168.100.5"
    "--port" "9001"
    "--name" "admin-vm"
    "--cacert" "/etc/givc/ca-cert.pem"
    "--cert" "/etc/givc/cert.pem"
    "--key" "/etc/givc/key.pem"
  )
else
  # Parse GIVC_ARGS into the array
  read -r -a args <<<"$GIVC_ARGS"
fi

VM="$1"
UNIT="$2"
TIMEOUT="$3"

# Optional inputs for expected unit status
EXPECTED_STATUS=""
if [ "$#" -ge 4 ]; then
  EXPECTED_STATUS="$4"
fi
SUB_STATUS=""
if [ "$#" -eq 5 ]; then
  SUB_STATUS="$5"
fi

# Wait until the unit is running
echo "Waiting for unit '$UNIT' in VM '$VM' ..."
SECONDS=0
while [ $SECONDS -lt "$TIMEOUT" ]; do
  if status_response="$(givc-cli "${args[@]}" get-status "$VM" "$UNIT" 2>/dev/null)"; then
    active_status=$(echo "$status_response" | sed -n 's/.*active_state: "\([^"]*\)".*/\1/p')
    sub_status=$(echo "$status_response" | sed -n 's/.*sub_state: "\([^"]*\)".*/\1/p')
    echo wait for unit status: "$active_status" "$sub_status"
    if [[ -n $EXPECTED_STATUS ]]; then
      if [[ -z $SUB_STATUS ]]; then
        # No sub-state eval
        [[ $active_status == "$EXPECTED_STATUS" ]] && exit 0
      else
        # Custom status and sub status
        [[ $active_status == "$EXPECTED_STATUS" && $sub_status == "$SUB_STATUS" ]] && exit 0
      fi
    else
      # Default to generic 'active' service eval
      [[ $active_status == "active" && ($sub_status == "active" || $sub_status == "running" || $sub_status == "exited") ]] && exit 0
    fi
  else
    echo "Waiting to get status for unit '$UNIT' in VM '$VM' ..."
  fi
  sleep 0.5
done
# The last observed state is what separates "slow to start" from "this never ran"; without
# it a permanently failing unit is indistinguishable from a timing hiccup. stderr so the
# caller's journal shows it as an error rather than progress.
echo "Timeout reached: Unit '$UNIT' in VM '$VM' did not reach the desired state within $TIMEOUT seconds (last observed: ${active_status:-unknown}/${sub_status:-unknown}). Exit gracefully." >&2
