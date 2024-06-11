# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.ghaf.services.storage;
  inherit (builtins) filter map listToAttrs;
  inherit (lib) mkIf optionals optionalAttrs optionalString forEach nameValuePair recursiveUpdate concatStringsSep unique foldl';

  # Helper functions
  filterHostShares = filter (s: s.tag != null && s.host-path != null) cfg.shares;
  vmShares = filter (s: s.target-vm != null) cfg.shares;
  filterSharesByName = vm: filter (s: s.target-vm == vm) vmShares;
  sharePaths = map (s: s.host-path) filterHostShares;
  vmList = unique (map (s: s.target-vm) vmShares);
  mergeAttrSets = attrSets: foldl' (a: b: recursiveUpdate a b) {} attrSets;

  # Share configuration
  shareConfigs = vm: {
    microvm.shares = forEach (filterSharesByName vm) (
      vmShare: {
        tag = "${vmShare.tag}";
        source = "${vmShare.host-path}";
        mountPoint = "${
          if (vmShare.tmp-path != null)
          then vmShare.tmp-path
          else vmShare.vm-path
        }";
        proto = "virtiofs";
      }
    );
  };

  # Service configuration
  serviceConfigs = vm:
    forEach (filterSharesByName vm) (vmShare: {
      environment.systemPackages = optionals (vmShare.tmp-path != null) [pkgs.umount];
      systemd.services."storage-prep-${vmShare.tag}" = let
        # Service to set owner, permissions, and (optionally) copy files
        prepStorage = pkgs.writeShellScriptBin "storage_prep" ''
          set -xeuo pipefail
          if [ ! -d "${vmShare.vm-path}" ]; then
            mkdir -p ${vmShare.vm-path}
          fi
          ${optionalString (vmShare.tmp-path != null) "cp -r ${vmShare.tmp-path}/* ${vmShare.vm-path}"}
          chown -R ${vmShare.target-owner}:${vmShare.target-group} ${vmShare.vm-path}
          chmod -R ${vmShare.target-permissions} ${vmShare.vm-path}
          ${optionalString (vmShare.tmp-path != null) "${pkgs.umount}/bin/umount ${vmShare.tmp-path}"}
        '';
      in
        {
          description = "Prepare host-shared files for ${vmShare.tag}";
          enable = true;
          path = [prepStorage];
          after = ["local-fs.target"];
          requiredBy = ["${vmShare.target-service}"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            Restart = "no";
            StandardOutput = "journal";
            StandardError = "journal";
            ExecStart = "${prepStorage}/bin/storage_prep";
          };
        }
        // optionalAttrs (vmShare.tmp-path != null) {
          unitConfig.ConditionPathExists = "${vmShare.tmp-path}";
        };
    });

  # Assemble VM config
  vmConfig = vm: {
    config = mergeAttrSets [
      (shareConfigs vm)
      (mergeAttrSets (serviceConfigs vm))
    ];
  };
in {
  config = mkIf cfg.enable {
    # Host directory generation
    systemd.services."storage-prep-host" = let
      prepStorage = pkgs.writeShellScriptBin "process_dirs" ''
        set -xeuo pipefail
        IFS=', ' read -r -a array <<< "${concatStringsSep " " sharePaths}"
        for path in "''${array[@]}"; do
          if [ ! -d "$path" ]; then
            mkdir -p $path
          fi
          chmod -R 770 $path
        done
      '';
    in {
      description = "Generate host storage directories";
      enable = true;
      path = [prepStorage];
      wantedBy = ["local-fs.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "no";
        StandardOutput = "journal";
        StandardError = "journal";
        ExecStart = "${prepStorage}/bin/process_dirs";
      };
    };

    # Extra VM config to be passed to the respective VMs
    microvm.vms = listToAttrs (
      map (vm: nameValuePair "${vm}" (vmConfig vm)) vmList
    );
  };
}
