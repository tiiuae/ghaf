# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.givc;
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    types
    filterAttrs
    concatStringsSep
    mapAttrsToList
    escapeShellArg
    strings
    ;

  # Filter policies that have a dest defined.
  startupPolicies = filterAttrs (_name: p: p.dest != null) cfg.policyClient.policies;
  appvmEnabled = config.ghaf.givc.appvm.enable;
  appUser = config.ghaf.users.appUser.name;
  policyUser = if appvmEnabled then appUser else "root";
  userUID = if appvmEnabled then config.ghaf.users.appUser.uid else 0;
  userGID = if appvmEnabled then 100 else 0;

  givcPolicyInitApp = pkgs.writeShellApplication {
    name = "givc-policy-init";
    runtimeInputs = [ pkgs.coreutils ];
    text = concatStringsSep "\n" (
      mapAttrsToList (
        name: p:
        let
          storageBin = "${cfg.policyClient.storePath}/${name}/policy.bin";
          dest = toString p.dest;
          factory = toString p.factory;
        in
        ''
          STORAGE_BIN=${escapeShellArg storageBin}
          DEST=${escapeShellArg dest}
          FACTORY=${escapeShellArg factory}

          mkdir -p "$(dirname "$DEST")"

          if [ -f "$STORAGE_BIN" ]; then
            echo "Initializing $DEST from local storage: $STORAGE_BIN"
            cp "$STORAGE_BIN" "$DEST"
            chown ${toString userUID}:${toString userGID} "$DEST"
            chmod 0755 "$DEST"
          elif [ -f "$FACTORY" ]; then
            echo "Initializing $DEST from factory: $FACTORY"
            cp "$FACTORY" "$DEST"
            chown ${toString userUID}:${toString userGID} "$DEST"
            chmod 0755 "$DEST"
          else
            echo "Error! file not found:$FACTORY"
          fi
        ''
      ) startupPolicies
    );
  };

  tmpFilesRules = lib.concatMap (
    value:
    lib.optional (
      value.dest != null && strings.trim value.dest != ""
    ) "d ${dirOf value.dest} 0755 ${toString userUID} ${toString userGID} -"
  ) (lib.attrValues cfg.policyClient.policies);

in
{
  options.ghaf.givc = {
    policyClient = {
      enable = mkEnableOption "Policy admin.";

      storePath = mkOption {
        type = types.path;
        default = "/etc/admin-policies";
        description = "Directory path for policy storage.";
      };
      policies = mkOption {
        type = types.attrsOf types.policy;
        default = { };
        description = "Definition of all managed policies.";
      };
    };
    policyAdmin = {
      enable = mkEnableOption "Policy admin.";
      storePath = mkOption {
        type = types.path;
        default = "/etc/policies";
        description = "Directory path for policy storage.";
      };
      updater = {
        gitURL = {
          enable = mkEnableOption "pulling updates from git";
          url = mkOption {
            type = types.str;
            default = "";
            description = "Git repository URL.";
          };
          ref = mkOption {
            type = types.str;
            default = "main";
            description = "Git reference (branch).";
          };
          poll_interval_secs = mkOption {
            type = types.int;
            default = 300;
            description = "Polling interval in seconds.";
          };
        };
        perPolicy = {
          enable = mkEnableOption "updates per policy from provided URL in VM policy";
        };
      };
    };
  };

  config = lib.mkMerge [
    # Admin configuration
    (mkIf (cfg.enable && cfg.policyAdmin.enable) {
      ghaf.storagevm = mkIf config.ghaf.storagevm.enable {
        directories = [
          {
            directory = cfg.policyAdmin.storePath;
            user = policyUser;
            group = policyUser;
            mode = "0774";
          }
        ];
      };
    })

    # Client configuration
    (mkIf (cfg.enable && cfg.policyClient.enable) {
      # Initialize startup policies
      systemd.services = {
        "givc-policy-init" = {
          description = "Initialize GIVC policies from factory or updates";
          wantedBy = [ "sysinit.target" ];
          after = [ "local-fs.target" ];
          before = [ "basic.target" ];
          unitConfig.DefaultDependencies = false;
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe givcPolicyInitApp;
          };
        };
      }
      // lib.concatMapAttrs (
        name: p:
        lib.optionalAttrs (p.script != null) {
          "givc-policy-${name}" = {
            description = "Trigger script for policy ${name}";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${p.script}";
            };
            onSuccess = p.depends;
          };
        }
      ) cfg.policyClient.policies;

      # Run script in a service for each policy on update
      systemd.paths = lib.concatMapAttrs (
        name: p:

        if p.script != null then
          {
            "givc-policy-${name}" = {
              pathConfig.PathModified = toString p.dest;
              wantedBy = [ "multi-user.target" ];
            };
          }
        else
          lib.listToAttrs (
            map (dep: {
              name = "givc-policy-${name}-${builtins.replaceStrings [ "." ] [ "-" ] dep}";
              value = {
                pathConfig = {
                  PathModified = toString p.dest;
                  Unit = dep;
                };
                unitConfig.Description = "Restart ${dep} when policy ${name} changes";
                wantedBy = [ "multi-user.target" ];
              };
            }) p.depends
          )

      ) cfg.policyClient.policies;

      ghaf.storagevm = mkIf config.ghaf.storagevm.enable {
        directories = [
          {
            directory = cfg.policyClient.storePath;
            user = policyUser;
            group = policyUser;
            mode = "0774";
          }
        ];
      };

      systemd.tmpfiles = mkIf appvmEnabled {
        rules = [
          "d ${cfg.policyClient.storePath} 0755 ${toString userUID} ${toString userGID} -"
        ]
        ++ tmpFilesRules;
      };
    })
  ];
}
