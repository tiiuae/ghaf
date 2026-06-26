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
    {
      options = {
        enable = mkEnableOption "SPIRE agent ${name}";

        serverAddress = mkOption {
          type = types.str;
          default = config.ghaf.common.spire.server.address;
          description = "SPIRE server address.";
        };

        serverPort = mkOption {
          type = types.port;
          default = config.ghaf.common.spire.server.port;
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
          type = types.str;
          default = config.ghaf.common.spire.server.trustDomain;
          description = "SPIFFE trust domain.";
        };

        nodeAttestationMode = mkOption {
          type = types.enum [
            "join_token"
            "x509pop"
          ];
          default = "x509pop";
          description = "Node attestation mode.";
        };

        workloads = mkOption {
          type = types.spireWorkloads;
          default = [ ];
          description = "List of workloads for this SPIRE agent.";
        };

        trustBundlePath = mkOption {
          type = types.str;
          default = "/etc/common/spire/bundle.pem";
          description = "Path to the SPIRE bootstrap trust bundle.";
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
          join_token.token = mkOption {
            type = types.str;
            default = "/etc/common/spire/tokens/${config.networking.hostName}.token";
            description = "Path to the server-generated join token.";
          };

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
  isJoinToken = agent: agent.nodeAttestationMode == "join_token";

  credentials =
    agent:
    if isJoinToken agent then
      [ "join-token:${agent.settings.join_token.token}" ]
    else
      [
        "key.pem:${agent.settings.x509pop.privateKeyPath}"
        "cert.pem:${agent.settings.x509pop.certificatePath}"
      ];

  credentialPaths =
    agent:
    if isJoinToken agent then
      [ agent.settings.join_token.token ]
    else
      [
        agent.settings.x509pop.privateKeyPath
        agent.settings.x509pop.certificatePath
      ];

  agentConf =
    agent:
    let
      nodeAttestor =
        if isJoinToken agent then
          ''
            NodeAttestor "join_token" {
              plugin_data {}
            }
          ''
        else
          ''
            NodeAttestor "x509pop" {
              plugin_data {
                private_key_path = "$CREDENTIALS_DIRECTORY/key.pem"
                certificate_path = "$CREDENTIALS_DIRECTORY/cert.pem"
              }
            }
          '';
    in
    ''
      agent {
        data_dir = "${agent.dataDir}"
        log_level = "${agent.logLevel}"
        server_address = "${agent.serverAddress}"
        server_port = ${toString agent.serverPort}
        trust_domain = "${agent.trustDomain}"
        trust_bundle_path = "${agent.trustBundlePath}"
        socket_path = "${agent.socketPath}"
        ${optionalString (isJoinToken agent) ''join_token_file = "$CREDENTIALS_DIRECTORY/join-token"''}
      }

      plugins {
        ${nodeAttestor}

        WorkloadAttestor "unix" {
          plugin_data {}
        }
        KeyManager "memory" {
          plugin_data {}
        }
      }
    '';

  configFiles = mapAttrs (
    name: agent: pkgs.writeText "${serviceName name}.conf" (agentConf agent)
  ) enabledAgents;

  waitForAgent =
    name: agent:
    pkgs.writeShellApplication {
      name = "wait-for-${serviceName name}";
      runtimeInputs = optionals agent.serverHealthCheck.enable [ pkgs.curl ];
      text = ''
        ${optionalString agent.serverHealthCheck.enable ''
          server_url="http://${agent.serverAddress}:${toString agent.serverHealthCheck.port}/ready"
          until curl --fail --silent --connect-timeout 1 --max-time 2 "$server_url" >/dev/null 2>&1; do
            echo "Waiting for SPIRE server at $server_url"
            sleep 1
          done
        ''}

        until [ -e ${escapeShellArg agent.trustBundlePath} ]; do
          echo "Waiting for SPIRE trust bundle ${agent.trustBundlePath}"
          sleep 1
        done

        ${optionalString (isJoinToken agent) ''
          until [ -e ${escapeShellArg agent.settings.join_token.token} ]; do
            echo "Waiting for SPIRE join token ${agent.settings.join_token.token}"
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
      ]
      ++ optional (!isJoinToken agent) "givc-key-setup.service";

      unitConfig.RequiresMountsFor = [
        agent.trustBundlePath
      ]
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
        RuntimeDirectoryMode = "0755";
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
  ) enabledAgents;
in
{
  _file = ./agent.nix;

  options.ghaf.security.spire.agents = mkOption {
    type = types.attrsOf agentType;
    default = { };
    description = "Named SPIRE agent instances.";
  };

  config = mkIf (enabledAgents != { }) {
    assertions = [
      {
        assertion =
          builtins.length (unique (map (agent: agent.socketPath) (builtins.attrValues enabledAgents)))
          == builtins.length (builtins.attrValues enabledAgents);
        message = "SPIRE agents must use unique socket paths.";
      }
    ];

    environment.systemPackages = [ spire-package ];

    users = {
      groups = mapAttrs' (name: _: nameValuePair (serviceName name) { }) enabledAgents;
      users = mapAttrs' (
        name: _:
        nameValuePair (serviceName name) {
          isSystemUser = true;
          group = serviceName name;
        }
      ) enabledAgents;
    };

    systemd = {
      services = agentServices;
      tmpfiles.rules = filter (rule: rule != "") (
        mapAttrsToList (
          name: agent:
          optionalString (
            !hasPrefix "/run/" agent.dataDir
          ) "d ${agent.dataDir} 0700 ${serviceName name} ${serviceName name} - -"
        ) enabledAgents
      );
    };
  };
}
