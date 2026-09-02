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
      pkgs.systemd
    ];
    text = ''
      # Same gate as the server-side refresh: with requireSync false (the x86
      # default) the barrier can release on a timeout with the clock still
      # untrusted, and restarting the agents then just re-mints bad identities.
      sync_state="$(cat /run/ghaf-clock-synced 2>/dev/null || echo missing)"
      if [ "$sync_state" != "synchronised" ]; then
        echo "spire-reattest-agents: clock barrier reports '$sync_state', not 'synchronised';" \
             "not re-attesting. Agents keep identities minted against an untrusted clock." >&2
        exit 0
      fi

      echo "spire-reattest-agents: clock synchronised, re-attesting ${toString (length agentServiceUnits)} agent(s)"
      systemctl restart ${escapeShellArgs agentServiceUnits}
    '';
  };

  waitForAgent =
    name: agent:
    pkgs.writeShellApplication {
      name = "wait-for-${serviceName name}";
      runtimeInputs = optionals (agent.serverHealthCheck.enable || agent.trustBundleUrl != null) [
        pkgs.curl
      ];
      text = ''
        ${optionalString agent.serverHealthCheck.enable ''
          server_url="http://${agent.serverAddress}:${toString agent.serverHealthCheck.port}/ready"
          until curl --fail --silent --connect-timeout 1 --max-time 2 "$server_url" >/dev/null 2>&1; do
            echo "Waiting for SPIRE server at $server_url"
            sleep 1
          done
        ''}

        ${optionalString (agent.trustBundleUrl != null) ''
          trust_bundle_url=${escapeShellArg agent.trustBundleUrl}
          until curl --fail --silent --location --connect-timeout 2 --max-time 5 --output /dev/null "$trust_bundle_url"; do
            echo "Waiting for SPIRE trust bundle URL $trust_bundle_url"
            sleep 1
          done
        ''}

        ${optionalString (agent.trustBundleUrl == null) ''
          # -s and a PEM check, not just -e: the server truncates and rewrites this file
          # in place, so a bare existence test lets the agent start against a zero-byte
          # or half-written bundle and fail its first handshake for no good reason.
          until [ -s ${escapeShellArg agent.trustBundlePath} ] \
            && grep -q "BEGIN CERTIFICATE" ${escapeShellArg agent.trustBundlePath}; do
            echo "Waiting for SPIRE trust bundle ${agent.trustBundlePath}"
            sleep 1
          done
        ''}

        # NOTE: passing the checks above does not prove the bundle is the *current* one.
        # trustBundlePath lives on persistent storage, so it outlives a reflash while the
        # server regenerates its CA; the agent then starts against a stale bundle and
        # crash-loops with "x509svid: could not verify leaf certificate: certificate
        # signed by unknown authority" until the server rewrites the file. Observed on an
        # AGX: ~40 restarts per VM per boot, and because Restart= keeps the unit in
        # activating/auto-restart it never reaches "failed", so `systemctl --failed` and
        # the test suite's VM status check both stay green while this is happening.
        #
        # Closing that properly means making bundle distribution authoritative rather than
        # best-effort -- spire-publish-bundle.service is still marked PoC and ships
        # inactive. Deliberately not papered over here with an mtime or freshness
        # heuristic: if the server does not rewrite the bundle on a given boot, such a
        # check would hang the agent forever instead of letting it retry, which is worse
        # than the loop it replaces.
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
