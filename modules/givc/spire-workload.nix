# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.givc.spireWorkload;
  inherit (lib)
    getExe
    mkIf
    mkMerge
    mkOption
    optional
    types
    unique
    ;

  trustDomain = config.ghaf.common.spire.server.trustDomain;
  agent = config.ghaf.security.spire.agents.downstream;
  agentService = "spire-agent.service";

  adminEnabled = config.givc.admin.enable;
  hostEnabled = config.givc.host.enable;
  sysvmEnabled = config.givc.sysvm.enable;
  appvmEnabled = config.givc.appvm.enable;
  hasGivcService = adminEnabled || hostEnabled || sysvmEnabled || appvmEnabled;

  appUser = config.ghaf.users.appUser;
  primaryUid = if appvmEnabled then appUser.uid else 0;

  # GUI-side GIVC clients run as the login user when the upstream sysvm
  # module explicitly enables user TLS access.
  userTlsAccess = sysvmEnabled && config.givc.sysvm.enableUserTlsAccess;
  homedUser = config.ghaf.users.homedUser;
  staticTlsUsers = lib.attrNames (
    lib.filterAttrs (_: user: user.isNormalUser or false) config.users.users
  );
  staticTlsUids = map (userName: config.users.users.${userName}.uid) (
    lib.filter (userName: config.users.users.${userName}.uid != null) staticTlsUsers
  );
  userTlsUids = unique (
    lib.optionals (userTlsAccess && homedUser.enable) [ homedUser.uid ]
    ++ lib.optionals userTlsAccess staticTlsUids
  );
  additionalUids = lib.filter (uid: uid != primaryUid) userTlsUids;

  workloadForUid = uid: {
    name = if uid == primaryUid then "givc" else "givc-user-${toString uid}";
    selectors = [ "unix:uid:${toString uid}" ];
  };

  spireTls = {
    enable = true;
    type = "spire";
    spire = {
      agentSocketPath = agent.socketPath;
      inherit trustDomain;
    };
  };

  systemTransportNames = unique (
    optional hostEnabled config.givc.host.network.agent.transport.name
    ++ optional sysvmEnabled config.givc.sysvm.network.agent.transport.name
  );
  userTransportNames = optional appvmEnabled config.givc.appvm.network.agent.transport.name;
  systemServiceNames =
    optional adminEnabled "givc-admin" ++ map (name: "givc-${name}") systemTransportNames;
  userServiceNames = map (name: "givc-${name}") userTransportNames;

  waitForWorkloadApi = pkgs.writeShellApplication {
    name = "wait-for-spire-workload-api";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      for _ in $(seq 1 60); do
        if [ -S ${lib.escapeShellArg agent.socketPath} ]; then
          exit 0
        fi
        sleep 1
      done

      echo "Timed out waiting for SPIRE Workload API socket ${agent.socketPath}" >&2
      exit 1
    '';
  };

  givcSystemServiceConfig = {
    after = [ agentService ];
    wants = [ agentService ];
    serviceConfig.ExecStartPre = [ (getExe waitForWorkloadApi) ];
  };
in
{
  _file = ./spire-workload.nix;

  options.ghaf.givc.spireWorkload.enable = mkOption {
    type = types.bool;
    default = false;
    description = ''
      Use the SPIRE Workload API to issue and rotate identities for the local
      GIVC services and clients.
    '';
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = config.ghaf.givc.enable && config.ghaf.givc.enableTls;
          message = "The GIVC SPIRE workload requires GIVC TLS to be enabled.";
        }
        {
          assertion = agent.enable;
          message = "The GIVC SPIRE workload requires the downstream SPIRE agent.";
        }
        {
          assertion = hasGivcService;
          message = "The GIVC SPIRE workload requires a local GIVC service.";
        }
      ];

      # GIVC daemons and CLI callers previously shared a certificate by Unix
      # user. Preserve that access boundary while letting GIVC consume and
      # rotate the SVID directly through the Workload API.
      ghaf.security.spire.agents.downstream.workloads = lib.mkAfter (
        map workloadForUid ([ primaryUid ] ++ additionalUids)
      );

      givc.admin.tls = mkIf adminEnabled spireTls;
      givc.host.network.tls = mkIf hostEnabled spireTls;
      givc.sysvm.network.tls = mkIf sysvmEnabled spireTls;
      givc.appvm.network.tls = mkIf appvmEnabled spireTls;

      # Non-root GIVC daemons and CLI callers need access to the agent socket.
      users.groups.spire-agent.members = lib.mkAfter (
        lib.optionals appvmEnabled [ appUser.name ] ++ lib.optionals userTlsAccess staticTlsUsers
      );
      ghaf.users.homedUser.extraGroups = mkIf (userTlsAccess && homedUser.enable) (
        lib.mkAfter [ "spire-agent" ]
      );

      # The static credentials in /etc/givc remain available to the x509pop
      # node attestor, but GIVC now obtains its own identity from SPIRE.
      systemd.services = {
        givc-user-key-setup.enable = lib.mkForce false;
      }
      // lib.genAttrs systemServiceNames (_: givcSystemServiceConfig);

      systemd.user.services = lib.genAttrs userServiceNames (_: {
        serviceConfig.ExecStartPre = [ (getExe waitForWorkloadApi) ];
      });
    }
  ]);
}
