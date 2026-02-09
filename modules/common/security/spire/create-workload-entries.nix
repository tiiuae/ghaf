# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  pkgs,
  lib,
  config,
  spire-package,
  socketPath,
  spireAgentVMs,
}:
let
  inherit (lib) escapeShellArg concatMapStringsSep;
in
pkgs.writeShellApplication {
  name = "spire-create-workload-entries";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.gawk
    pkgs.gnugrep
    spire-package
  ];
  text = ''
    SOCKET="${socketPath}"
    echo "=== SPIRE Workload Entry Creator ==="

    # Wait for server
    echo "Waiting for SPIRE server..."
    while true; do
      if spire-server healthcheck -socketPath "$SOCKET" >/dev/null 2>&1; then
        echo "Server ready"
        break
      fi
      sleep 2
    done

    create_entry() {
      local parentID="$1"
      local spiffeID="$2"
      local is_node="$3"
      shift 3
      local selectors=("$@")

      if spire-server entry show -socketPath "$SOCKET" -spiffeID "$spiffeID" >/dev/null 2>&1; then
        echo "Entry exists: $spiffeID"
        return
      fi

      echo "Creating entry: $spiffeID"
      local cmd=(spire-server entry create -socketPath "$SOCKET" -spiffeID "$spiffeID")

      if [ "$is_node" = "true" ]; then
        cmd+=(-node)
      else
        cmd+=(-parentID "$parentID")
      fi

      for s in "''${selectors[@]}"; do
        cmd+=(-selector "$s")
      done

      "''${cmd[@]}"
    }

    ${concatMapStringsSep "\n" (
      vmName:
      let
        agentCfg = config.ghaf.common.spire.agents.${vmName};
        agentSpiffeID = "spiffe://${config.ghaf.common.spire.server.trustDomain}/${vmName}";

        nodeEntryCmd =
          if (agentCfg.nodeAttestationMode == "x509pop") then
            ''
              create_entry "" ${escapeShellArg agentSpiffeID} "true" "x509pop:subject:cn:${escapeShellArg vmName}"
            ''
          else
            "";

        workloadCmds = concatMapStringsSep "\n" (
          workload:
          let
            workloadSpiffeID = "spiffe://${config.ghaf.common.spire.server.trustDomain}/${vmName}/${workload.name}";
            selectors = concatMapStringsSep " " escapeShellArg workload.selectors;
          in
          ''
            create_entry ${escapeShellArg agentSpiffeID} ${escapeShellArg workloadSpiffeID} "false" ${selectors}
          ''
        ) agentCfg.workloads;
      in
      nodeEntryCmd + workloadCmds
    ) spireAgentVMs}

    echo "Node and workload entries created successfully."
  '';
}
