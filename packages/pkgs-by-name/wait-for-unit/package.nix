# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  writeShellApplication,
  grpcurl,
  jq,
}:
writeShellApplication {
  name = "wait-for-unit";

  runtimeInputs = [
    grpcurl
    jq
  ];

  text = ''
    # Assert root
    [[ $(id -u) -ne 0 ]] && echo "Please run as root." && exit 1

    # Usage
    if [ "$#" -ne 5 ]; then
      echo "Usage: $0 <admin service ip> <admin service port> <vm-name> <unit-name> <timeout in seconds>"
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
    SECONDS=0

    # Wait until the unit is running
    echo "Waiting for unit '$UNIT' in VM '$VM' ..."
    while [ $SECONDS -lt "$TIMEOUT" ]; do
      if status_response="$(grpcurl "''${args[@]}" 2>/dev/null)"; then
        active_status=$(echo "$status_response" | jq -rj '.ActiveState')
        sub_status=$(echo "$status_response" | jq -rj '.SubState')
        [[ "$active_status" == "active" && ("$sub_status" == "active" || "$sub_status" == "running" || "$sub_status" == "exited") ]] && exit 0
      else
        echo "Waiting to get status for unit '$UNIT' in VM '$VM' ..."
      fi
      sleep 0.5
    done
    echo "Timeout reached: Unit '$UNIT' in VM '$VM' did not reach the desired state within $TIMEOUT seconds. Exit gracefully."
  '';

  meta = {
    description = "Script to query a systemd unit status across VMs.";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
