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
          until [ -e ${escapeShellArg agent.trustBundlePath} ]; do
            echo "Waiting for SPIRE trust bundle ${agent.trustBundlePath}"
            sleep 1
          done
        ''}
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
        "network-online.target"
        "local-fs.target"
      ];
      after = [
        "network-online.target"
        "local-fs.target"
        "givc-key-setup.service"
      ];

      unitConfig.RequiresMountsFor =
        optional (agent.trustBundleUrl == null) agent.trustBundlePath
        ++ credentialPaths agent
        ++ optional (!hasPrefix "/run/" agent.dataDir) agent.dataDir;

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
      services = agentServices;
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
