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
    pkgs.jq
    spire-package
  ];
  text = ''
    SOCKET="${socketPath}"
    MANAGED_HINT_PREFIX="ghaf-managed/"
    declare -A desired_entry_keys=()
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

    update_entry() {
      local entry_id="$1"
      local parentID="$2"
      local spiffeID="$3"
      local managed_hint="$4"
      local dns_count="$5"
      shift 5

      local dns_names=()
      local i
      for ((i = 0; i < dns_count; i++)); do
        dns_names+=("$1")
        shift
      done
      local selectors=("$@")

      local cmd=(
        spire-server entry update
        -socketPath "$SOCKET"
        -entryID "$entry_id"
        -parentID "$parentID"
        -spiffeID "$spiffeID"
        -hint "$managed_hint"
      )

      for selector in "''${selectors[@]}"; do
        cmd+=(-selector "$selector")
      done

      for dns_name in "''${dns_names[@]}"; do
        cmd+=(-dns "$dns_name")
      done

      "''${cmd[@]}"
    }

    create_entry() {
      local parentID="$1"
      local spiffeID="$2"
      local is_node="$3"
      local managed_hint="$4"
      local dns_count="$5"
      shift 5

      local dns_names=()
      local i
      for ((i = 0; i < dns_count; i++)); do
        dns_names+=("$1")
        shift
      done
      local selectors=("$@")

      desired_entry_keys["$managed_hint $spiffeID"]=1

      local entries_json
      entries_json="$(
        spire-server entry show \
          -socketPath "$SOCKET" \
          -spiffeID "$spiffeID" \
          -output json
      )"

      local desired_selectors
      local desired_dns_names
      desired_selectors="$(
        printf '%s\n' "''${selectors[@]}" |
          jq -Rsc 'split("\n") | map(select(length > 0)) | sort'
      )"
      desired_dns_names="$(
        printf '%s\n' "''${dns_names[@]}" |
          jq -Rsc 'split("\n") | map(select(length > 0)) | sort'
      )"

      local entry_summary
      entry_summary="$(
        jq -c \
          --arg managedHint "$managed_hint" \
          --arg parentID "$parentID" \
          --argjson selectors "$desired_selectors" \
          --argjson dnsNames "$desired_dns_names" \
          '
            def id_string:
              "spiffe://\(.trust_domain)\(.path)";
            def has_desired_shape:
              ((.parent_id | id_string) == $parentID)
              and (((.selectors // []) | map(.type + ":" + .value) | sort) == $selectors)
              and (((.dns_names // []) | sort) == $dnsNames)
              and ((.admin // false) == false)
              and ((.downstream // false) == false)
              and (((.federates_with // []) | length) == 0)
              and ((.store_svid // false) == false)
              and (((.x509_svid_ttl // 0) | tonumber) == 0)
              and (((.jwt_svid_ttl // 0) | tonumber) == 0)
              and (((.expires_at // 0) | tonumber) == 0)
              and ((.additional_attributes.disable_x509_svid_prefetch // false) == false);
            {
              managed_ids: [
                .entries[]?
                | select((.hint // "") == $managedHint)
                | .id
              ],
              managed_exact_ids: [
                .entries[]?
                | select((.hint // "") == $managedHint)
                | select(has_desired_shape)
                | .id
              ],
              legacy_exact_ids: [
                .entries[]?
                | select((.hint // "") == "")
                | select(has_desired_shape)
                | .id
              ]
            }
          ' <<<"$entries_json"
      )"

      local managed_count
      local managed_exact_count
      local legacy_exact_count
      managed_count="$(jq -er '.managed_ids | length' <<<"$entry_summary")"
      managed_exact_count="$(jq -er '.managed_exact_ids | length' <<<"$entry_summary")"
      legacy_exact_count="$(jq -er '.legacy_exact_ids | length' <<<"$entry_summary")"

      if [ "$managed_count" -gt 0 ]; then
        local primary_id
        if [ "$managed_exact_count" -gt 0 ]; then
          primary_id="$(jq -er '.managed_exact_ids[0]' <<<"$entry_summary")"
          echo "Entry is current: $spiffeID"
        else
          primary_id="$(jq -er '.managed_ids[0]' <<<"$entry_summary")"
          echo "Updating changed managed entry: $spiffeID"
          update_entry \
            "$primary_id" "$parentID" "$spiffeID" "$managed_hint" "$dns_count" \
            "''${dns_names[@]}" "''${selectors[@]}"
        fi

        # Collapse duplicate managed entries, but leave every unmanaged entry alone.
        while IFS= read -r entry_id; do
          if [ "$entry_id" != "$primary_id" ]; then
            echo "Deleting duplicate managed entry: $spiffeID ($entry_id)"
            spire-server entry delete -socketPath "$SOCKET" -entryID "$entry_id"
          fi
        done < <(jq -r '.managed_ids[]' <<<"$entry_summary")
        return
      fi

      if [ "$legacy_exact_count" -eq 1 ]; then
        local legacy_entry_id
        legacy_entry_id="$(jq -er '.legacy_exact_ids[0]' <<<"$entry_summary")"
        echo "Adopting exact legacy entry: $spiffeID"
        update_entry \
          "$legacy_entry_id" "$parentID" "$spiffeID" "$managed_hint" "$dns_count" \
          "''${dns_names[@]}" "''${selectors[@]}"
        return
      fi

      if [ "$legacy_exact_count" -gt 1 ]; then
        echo "Multiple exact legacy entries found; leaving them unmanaged: $spiffeID" >&2
      fi

      echo "Creating entry: $spiffeID"
      local cmd=(
        spire-server entry create
        -socketPath "$SOCKET"
        -spiffeID "$spiffeID"
        -hint "$managed_hint"
      )

      if [ "$is_node" = "true" ]; then
        cmd+=(-node)
      else
        cmd+=(-parentID "$parentID")
      fi

      for s in "''${selectors[@]}"; do
        cmd+=(-selector "$s")
      done

      for dns_name in "''${dns_names[@]}"; do
        cmd+=(-dns "$dns_name")
      done

      "''${cmd[@]}"
    }

    prune_stale_managed_entries() {
      local managed_entries_json
      managed_entries_json="$(
        spire-server entry show \
          -socketPath "$SOCKET" \
          -output json
      )"

      while IFS=$'\t' read -r entry_id entry_hint entry_spiffe_id; do
        if [ -z "$entry_id" ]; then
          continue
        fi
        if [ -z "''${desired_entry_keys["$entry_hint $entry_spiffe_id"]+x}" ]; then
          echo "Deleting stale managed entry: $entry_spiffe_id ($entry_id)"
          spire-server entry delete -socketPath "$SOCKET" -entryID "$entry_id"
        fi
      done < <(
        jq -r \
          --arg managedHintPrefix "$MANAGED_HINT_PREFIX" \
          '
            .entries[]?
            | select((.hint // "") | startswith($managedHintPrefix))
            | [
                .id,
                .hint,
                ("spiffe://\(.spiffe_id.trust_domain)\(.spiffe_id.path)")
              ]
            | @tsv
          ' <<<"$managed_entries_json"
      )
    }

    ${concatMapStringsSep "\n" (
      vmName:
      let
        agentCfg = config.ghaf.common.spire.agents.${vmName};
        agentSpiffeID = "spiffe://${config.ghaf.common.spire.server.trustDomain}/${vmName}";
        serverSpiffeID = "spiffe://${config.ghaf.common.spire.server.trustDomain}/spire/server";

        nodeEntryCmd = ''
          create_entry ${escapeShellArg serverSpiffeID} ${escapeShellArg agentSpiffeID} "true" "ghaf-managed/node" "0" ${escapeShellArg "x509pop:subject:cn:${vmName}"}
        '';

        workloadCmds = concatMapStringsSep "\n" (
          workload:
          let
            workloadSpiffeID = "spiffe://${config.ghaf.common.spire.server.trustDomain}/${vmName}/${workload.name}";
            managedHint = "ghaf-managed/${workload.name}";
            dnsNames = concatMapStringsSep " " escapeShellArg workload.dnsNames;
            selectors = concatMapStringsSep " " escapeShellArg workload.selectors;
          in
          ''
            create_entry ${escapeShellArg agentSpiffeID} ${escapeShellArg workloadSpiffeID} "false" ${escapeShellArg managedHint} ${toString (builtins.length workload.dnsNames)} ${dnsNames} ${selectors}
          ''
        ) agentCfg.workloads;
      in
      nodeEntryCmd + workloadCmds
    ) spireAgentVMs}

    prune_stale_managed_entries
    echo "Node and workload entries created successfully."
  '';
}
