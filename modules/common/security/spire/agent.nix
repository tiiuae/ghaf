# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  spire-package = config.ghaf.common.spire.package;

  serviceName = name: if name == "downstream" then "spire-agent" else "spire-agent-${name}";
  runtimeDir = name: "/run/${serviceName name}";

  agentType = types.submodule (
    { name, ... }:
    let
      localServerDefault = value: if name == "downstream" then value else null;
    in
    {
      options = {
        enable = mkEnableOption "SPIRE agent ${name}";

        serverAddress = mkOption {
          type = types.nullOr types.str;
          default = localServerDefault config.ghaf.common.spire.server.address;
          description = "SPIRE server address.";
        };

        serverPort = mkOption {
          type = types.nullOr types.port;
          default = localServerDefault config.ghaf.common.spire.server.port;
          description = "SPIRE server agent port.";
        };

        serverHealthCheck = {
          enable = mkOption {
            type = types.bool;
            default = name == "downstream";
            description = "Wait for the SPIRE server readiness endpoint before starting.";
          };

          port = mkOption {
            type = types.port;
            default = config.ghaf.common.spire.server.healthCheckPort;
            description = "SPIRE server readiness endpoint port.";
          };
        };

        trustDomain = mkOption {
          type = types.nullOr types.str;
          default = localServerDefault config.ghaf.common.spire.server.trustDomain;
          description = "SPIFFE trust domain.";
        };

        nodeAttestationMode = mkOption {
          type = types.spireNodeAttestationMode;
          default = "x509pop";
          description = "Node attestation mode.";
        };

        workloads = mkOption {
          type = types.spireWorkloads;
          default = [ ];
          description = "List of workloads for this SPIRE agent.";
        };

        trustBundlePath = mkOption {
          type = types.nullOr types.str;
          default = localServerDefault "/etc/common/spire/bundle.pem";
          description = "Path to the SPIRE bootstrap trust bundle.";
        };

        trustBundleUrl = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            HTTPS URL for the SPIRE bootstrap trust bundle, validated against the system CA store.
            Prefer trustBundlePath when an out-of-band pinned bundle is available.
          '';
        };

        dataDir = mkOption {
          type = types.str;
          default = runtimeDir name;
          description = "SPIRE agent data directory.";
        };

        socketPath = mkOption {
          type = types.str;
          default = "${runtimeDir name}/agent.sock";
          description = "SPIFFE Workload API socket path.";
        };

        logLevel = mkOption {
          type = types.str;
          default = "INFO";
          description = "SPIRE agent log level.";
        };

        settings = {
          x509pop = {
            privateKeyPath = mkOption {
              type = types.str;
              default = "/etc/givc/key.pem";
              description = "Path to the X.509 node-attestation private key.";
            };

            certificatePath = mkOption {
              type = types.str;
              default = "/etc/givc/cert.pem";
              description = "Path to the X.509 node-attestation certificate.";
            };
          };
        };
      };
    }
  );

  enabledAgents = filterAttrs (_: agent: agent.enable) config.ghaf.security.spire.agents;
  hasValue = value: value != null && value != "";
  connectionConfigured =
    agent:
    hasValue agent.serverAddress
    && agent.serverPort != null
    && hasValue agent.trustDomain
    && (hasValue agent.trustBundleUrl || hasValue agent.trustBundlePath);
  trustBundleUrlIsSecure =
    agent: agent.trustBundleUrl == null || hasPrefix "https://" agent.trustBundleUrl;
  configuredAgents = filterAttrs (_: connectionConfigured) enabledAgents;

  credentials = agent: [
    "key.pem:${agent.settings.x509pop.privateKeyPath}"
    "cert.pem:${agent.settings.x509pop.certificatePath}"
  ];

  credentialPaths = agent: [
    agent.settings.x509pop.privateKeyPath
    agent.settings.x509pop.certificatePath
  ];

  trustBundleConfig =
    agent:
    if agent.trustBundleUrl != null then
      ''trust_bundle_url = "${agent.trustBundleUrl}"''
    else
      ''trust_bundle_path = "${agent.trustBundlePath}"'';

  agentConf = agent: ''
    agent {
      data_dir = "${agent.dataDir}"
      log_level = "${agent.logLevel}"
      server_address = "${agent.serverAddress}"
      server_port = ${toString agent.serverPort}
      trust_domain = "${agent.trustDomain}"
      ${trustBundleConfig agent}
      socket_path = "${agent.socketPath}"
      rebootstrap_mode = "auto"
      rebootstrap_delay = "0s"
    }

    plugins {
      NodeAttestor "x509pop" {
        plugin_data {
          private_key_path = "$CREDENTIALS_DIRECTORY/key.pem"
          certificate_path = "$CREDENTIALS_DIRECTORY/cert.pem"
        }
      }

      WorkloadAttestor "unix" {
        plugin_data {}
      }
      WorkloadAttestor "systemd" {
        plugin_data {}
      }
      KeyManager "memory" {
        plugin_data {}
      }
    }
  '';

  configFiles = mapAttrs (
    name: agent: pkgs.writeText "${serviceName name}.conf" (agentConf agent)
  ) configuredAgents;

  agentServiceUnits = map (name: "${serviceName name}.service") (builtins.attrNames configuredAgents);

  reattestAgentsApp = pkgs.writeShellApplication {
    name = "spire-reattest-agents";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.openssl
      pkgs.systemd
    ];
    text = ''
      # The boot barrier can time out before NTP synchronises on a later clock change.
      sync_state="$(cat /run/ghaf-clock-synced 2>/dev/null || echo missing)"
      if [ "$sync_state" != "synchronised" ] \
        && [ "$(timedatectl show -p NTPSynchronized --value)" != "yes" ]; then
        echo "spire-reattest-agents: clock barrier reports '$sync_state' and NTP is not synchronised;" \
             "not re-attesting." >&2
        exit 0
      fi

      tmp="$(mktemp -d)"
      trap 'rm -rf "$tmp"' EXIT

      agent_valid() {
        systemctl is-active --quiet "$unit" && [ -S "$socket" ] \
          && cp "$data" "$tmp/data.json" \
          && jq -er '.svid | select(length > 0) | map(@base64d) | join("")' "$tmp/data.json" > "$tmp/svid.pem" \
          && jq -er '.bundle | select(length > 0) | map(@base64d) | join("")' "$tmp/data.json" > "$tmp/bundle.pem" \
          && openssl verify -CAfile "$tmp/bundle.pem" -untrusted "$tmp/svid.pem" "$tmp/svid.pem" \
          && timeout 5 openssl s_client -connect "$endpoint" -alpn h2 \
            -CAfile "$tmp/bundle.pem" -verify_return_error </dev/null >/dev/null 2>&1
      }

      ${concatStringsSep "\n" (
        mapAttrsToList (name: agent: ''
          unit=${escapeShellArg "${serviceName name}.service"}
          socket=${escapeShellArg agent.socketPath}
          data=${escapeShellArg "${agent.dataDir}/agent-data.json"}
          endpoint=${escapeShellArg "${if hasInfix ":" agent.serverAddress then "[${agent.serverAddress}]" else agent.serverAddress}:${toString agent.serverPort}"}
          if agent_valid; then
            echo "$unit: credentials and server connection are valid; no restart needed."
          else
            ${getExe (waitForAgent name agent)}
            # Allow an attestation already in progress to finish against the ready server.
            if [ "$(systemctl show -p ActiveState --value "$unit")" = activating ]; then
              systemctl start "$unit" || true
            fi
            if agent_valid; then
              echo "$unit: recovered without a restart."
            else
              echo "$unit: credentials or connection are invalid; re-attesting."
              systemctl reset-failed "$unit"
              systemctl restart "$unit"
            fi
          fi
        '') configuredAgents
      )}
    '';
  };

  waitForAgent =
    name: agent:
    pkgs.writeShellApplication {
      name = "wait-for-${serviceName name}";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.curl
        pkgs.openssl
      ];
      text = ''
        ${optionalString agent.serverHealthCheck.enable ''
          server_url="http://${agent.serverAddress}:${toString agent.serverHealthCheck.port}/ready"
          until curl --fail --silent --connect-timeout 1 --max-time 2 "$server_url" >/dev/null 2>&1; do
            echo "Waiting for SPIRE server at $server_url"
            sleep 1
          done
        ''}

        tmp="$(mktemp -d)"
        trap 'rm -rf "$tmp"' EXIT
        endpoint=${escapeShellArg "${if hasInfix ":" agent.serverAddress then "[${agent.serverAddress}]" else agent.serverAddress}:${toString agent.serverPort}"}
        # Readiness alone does not prove that the distributed bundle trusts the server.
        until ${
          if agent.trustBundleUrl != null then
            ''curl --fail --silent --location --connect-timeout 2 --max-time 5 ${escapeShellArg agent.trustBundleUrl} -o "$tmp/bundle.pem"''
          else
            ''cp ${escapeShellArg agent.trustBundlePath} "$tmp/bundle.pem"''
        } \
          && timeout 5 openssl s_client -connect "$endpoint" -alpn h2 \
            -CAfile "$tmp/bundle.pem" -verify_return_error </dev/null >/dev/null 2>&1; do
          echo "Waiting for a valid SPIRE server certificate and matching trust bundle"
          sleep 1
        done
      '';
    };

  # systemd marks a Type=simple unit active as soon as the process forks, which
  # for spire-agent is *before* node attestation. The re-attest restart then
  # cancels an agent mid-attestation and it exits 1 ("Agent crashed: context
  # canceled"), so a deliberate restart is recorded as a failed unit on every
  # appvm. SPIRE only starts the Workload API once it has an SVID
  waitForAgentReady =
    name: agent:
    pkgs.writeShellApplication {
      name = "wait-ready-${serviceName name}";
      runtimeInputs = [ pkgs.coreutils ];
      text = ''
        socket=${escapeShellArg agent.socketPath}
        for _ in $(seq 1 90); do
          if [ -S "$socket" ]; then
            exit 0
          fi
          sleep 1
        done
        echo "${serviceName name}: workload API socket $socket did not appear in 90s;" \
             "continuing without the readiness gate." >&2
      '';
    };

  agentServices = mapAttrs' (
    name: agent:
    let
      unitName = serviceName name;
    in
    nameValuePair unitName {
      description = "SPIRE agent ${name}";
      wantedBy = [ "multi-user.target" ];
      requires = [
        "network.target"
        "local-fs.target"
      ];
      after = [
        "network.target"
        "local-fs.target"
        "givc-key-setup.service"
      ];

      unitConfig = {
        RequiresMountsFor =
          optional (agent.trustBundleUrl == null) agent.trustBundlePath
          ++ credentialPaths agent
          ++ optional (!hasPrefix "/run/" agent.dataDir) agent.dataDir;

        # An agent that cannot attest retries every 5s. Without a limit it never
        # reaches "failed", so it never appears in `systemctl --failed` and a
        # permanently broken identity looks exactly like a healthy device. That
        # is the failure mode the clock barrier used to prevent by refusing to
        # start the agent at all; now that the agent deliberately starts before
        # the clock is trusted, the visibility has to come from here instead.
        #
        # The window is wide enough to ride out the expected transient: after
        # the clock syncs, agents re-attest at roughly the same moment the
        # server rotates its CA, so a few failures against the old bundle are
        # normal. rebootstrap_mode = "auto" is the intended backstop for that
        # race -- if it is not permitted server-side the agent says so, and this
        # limit is what makes the resulting dead end visible rather than silent.
        StartLimitIntervalSec = 600;
        StartLimitBurst = 20;
      };

      serviceConfig = {
        ExecStartPre = [
          (getExe (waitForAgent name agent))
          (pkgs.writeShellScript "validate-${unitName}" ''
            exec ${getExe' spire-package "spire-agent"} validate \
              -expandEnv \
              -config ${escapeShellArg configFiles.${name}}
          '')
        ];
        ExecStart = "${getExe' spire-package "spire-agent"} run -expandEnv -config ${configFiles.${name}}";
        # Hold the unit in "activating" until the agent is actually attested and
        # serving; see waitForAgentReady above.
        ExecStartPost = getExe (waitForAgentReady name agent);
        LoadCredential = credentials agent;
        User = unitName;
        Group = unitName;
        RuntimeDirectory = unitName;
        RuntimeDirectoryMode = if name == "downstream" then "0755" else "0750";
        Restart = "on-failure";
        RestartSec = "5s";
        UMask = "0027";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = unique [
          agent.dataDir
          (runtimeDir name)
        ];
      };
    }
  ) configuredAgents;
in
{
  _file = ./agent.nix;

  options.ghaf.security.spire.agents = mkOption {
    type = types.attrsOf agentType;
    default = { };
    description = "Named SPIRE agent instances.";
  };

  config = mkIf (enabledAgents != { }) {
    assertions =
      mapAttrsToList (name: agent: {
        assertion = connectionConfigured agent;
        message = ''
          Enabled SPIRE agent "${name}" must configure serverAddress, serverPort,
          trustDomain, and either trustBundleUrl or trustBundlePath.
        '';
      }) enabledAgents
      ++ mapAttrsToList (name: agent: {
        assertion = trustBundleUrlIsSecure agent;
        message = "SPIRE agent \"${name}\" trustBundleUrl must use HTTPS.";
      }) enabledAgents
      ++ [
        {
          assertion =
            builtins.length (unique (map (agent: agent.socketPath) (builtins.attrValues enabledAgents)))
            == builtins.length (builtins.attrValues enabledAgents);
          message = "SPIRE agents must use unique socket paths.";
        }
      ];

    environment.systemPackages = [ spire-package ];

    users = {
      groups = mapAttrs' (name: _: nameValuePair (serviceName name) { }) configuredAgents;
      users = mapAttrs' (
        name: _:
        nameValuePair (serviceName name) {
          isSystemUser = true;
          group = serviceName name;
        }
      ) configuredAgents;
    };

    systemd = {
      services = agentServices // {
        spire-reattest-agents-after-time-sync = {
          description = "Re-attest SPIRE agents after time synchronisation";
          wantedBy = [ "ghaf-clock-synced.target" ];
          after = [ "ghaf-wait-time-sync.service" ] ++ agentServiceUnits;
          serviceConfig = {
            Type = "oneshot";
            ExecStart = getExe reattestAgentsApp;
            # Harmless clock steps must not exhaust the default unit start limit.
            ExecStartPost = "${pkgs.systemd}/bin/systemctl reset-failed spire-reattest-agents-after-time-sync.service";
            TimeoutStartSec = "120s";
          };
        };
      };
      timers.spire-clock-sync-trigger = {
        description = "Start the Ghaf clock synchronisation barrier asynchronously";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "0s";
          AccuracySec = "1us";
          Unit = "ghaf-clock-synced.target";
        };
      };
      timers.spire-reattest-agents-after-time-sync = {
        description = "Re-attest SPIRE agents after clock changes";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnClockChange = true;
          Unit = "spire-reattest-agents-after-time-sync.service";
        };
      };
      tmpfiles.rules = filter (rule: rule != "") (
        mapAttrsToList (
          name: agent:
          optionalString (
            !hasPrefix "/run/" agent.dataDir
          ) "d ${agent.dataDir} 0700 ${serviceName name} ${serviceName name} - -"
        ) configuredAgents
      );
    };
  };
}
