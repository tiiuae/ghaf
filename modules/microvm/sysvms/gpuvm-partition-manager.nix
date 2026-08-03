# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.virtualization.gpuPartitionManager;
  manager = inputs.gpu-partition-manager.lib.mkManager {
    inherit pkgs;
    cudaHeaders = pkgs.nvidia-jetpack.cudaPackages.cuda_cudart;
    cudaDriver = pkgs.nvidia-jetpack.l4t-cuda;
  };
  probe = pkgs.callPackage ../../../packages/gpu-vm-green-context-probe/package.nix {
    inherit (pkgs) nvidia-jetpack;
  };
  pluginLabel = plugin: plugin.pname or plugin.name or (toString plugin);
  pluginsWithoutName = lib.filter (plugin: !(plugin ? gpuPartitionPluginName)) cfg.plugins;
  pluginsWithWrongAbi = lib.filter (
    plugin: (plugin.requiredPluginAbiVersion or null) != manager.pluginAbiVersion
  ) cfg.plugins;
  pluginNames = map (plugin: plugin.gpuPartitionPluginName or null) cfg.plugins;
  duplicatePluginNames = lib.unique (
    lib.filter (
      name: name != null && lib.count (candidate: candidate == name) pluginNames > 1
    ) pluginNames
  );
  validatedPlugins = pkgs.runCommand "gpu-partition-manager-plugins" { } ''
    mkdir -p $out/lib/gpu-partition-manager
    ${lib.concatMapStringsSep "\n" (plugin: ''
      if [ ! -f ${plugin}/lib/gpu-partition-manager/plugin.so ]; then
        echo "${pluginLabel plugin}: missing lib/gpu-partition-manager/plugin.so" >&2
        exit 1
      fi
      ln -s ${plugin}/lib/gpu-partition-manager/plugin.so \
        $out/lib/gpu-partition-manager/${plugin.gpuPartitionPluginName or "invalid"}.so
    '') cfg.plugins}
  '';
  pluginArguments = lib.concatMap (plugin: [
    "--plugin"
    "${validatedPlugins}/lib/gpu-partition-manager/${plugin.gpuPartitionPluginName or "invalid"}.so"
  ]) cfg.plugins;
in
{
  _file = ./gpuvm-partition-manager.nix;

  options.ghaf.virtualization.gpuPartitionManager = {
    enable = lib.mkEnableOption "cooperative CUDA Green Context job manager";

    plugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = ''
        Trusted Nix packages implementing the gpu-partition-manager ABI.
        Each package must expose gpuPartitionPluginName and
        requiredPluginAbiVersion, and install its shared object at
        lib/gpu-partition-manager/plugin.so.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.plugins != [ ];
        message = "gpuPartitionManager requires at least one trusted plugin";
      }
      {
        assertion = lib.all (plugin: plugin ? gpuPartitionPluginName) cfg.plugins;
        message = "gpuPartitionManager plugins missing gpuPartitionPluginName: ${
          lib.concatMapStringsSep ", " pluginLabel pluginsWithoutName
        }";
      }
      {
        assertion = pluginsWithWrongAbi == [ ];
        message = "gpuPartitionManager plugins missing or not using manager ABI ${toString manager.pluginAbiVersion}: ${
          lib.concatMapStringsSep ", " pluginLabel pluginsWithWrongAbi
        }";
      }
      {
        assertion = duplicatePluginNames == [ ];
        message = "gpuPartitionManager plugin names must be unique; duplicated names: ${lib.concatStringsSep ", " duplicatePluginNames}";
      }
    ];

    users.groups.gpu-partition = { };
    users.users = {
      gpu-partition = {
        isSystemUser = true;
        group = "gpu-partition";
        extraGroups = [ "video" ];
      };
      ghaf.extraGroups = [ "gpu-partition" ];
    };

    environment.systemPackages = [
      manager
      probe
    ];

    systemd.services.gpu-partition-manager = {
      description = "Managed CUDA Green Context jobs";
      wantedBy = [ "multi-user.target" ];
      wants = [ "gpu-vm-node-access.service" ];
      after = [ "gpu-vm-node-access.service" ];
      unitConfig = {
        StartLimitIntervalSec = 300;
        StartLimitBurst = 12;
      };
      serviceConfig = {
        Type = "simple";
        User = "gpu-partition";
        Group = "gpu-partition";
        RuntimeDirectory = "gpu-partition-manager";
        RuntimeDirectoryMode = "0750";
        UMask = "0007";
        ExecStart = lib.escapeShellArgs ([ "${manager}/bin/gpu-partition-manager" ] ++ pluginArguments);
        Restart = "on-failure";
        RestartSec = 10;
        # 78 = EX_CONFIG: the daemon exits with this when the GPU geometry
        # cannot be split evenly. Never restart into an unsupported geometry.
        RestartPreventExitStatus = 78;
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateNetwork = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = [ "AF_UNIX" ];
        CapabilityBoundingSet = [ "" ];
        RestrictNamespaces = true;
        RestrictSUIDSGID = true;
        RestrictRealtime = true;
        RemoveIPC = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ProtectProc = "invisible";
        SystemCallArchitectures = "native";
        LockPersonality = true;
      };
    };
  };
}
