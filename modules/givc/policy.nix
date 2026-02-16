# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{
  config,
  lib,
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
    mapAttrs'
    nameValuePair
    listToAttrs
    flatten
    strings
    ;

  # Filter policies that have both factory and dest defined.
  startupPolicies = filterAttrs (_name: p: p.dest != null) cfg.policyClient.policies;

  tmpFilesRules = lib.flatten (
    lib.mapAttrsToList (
      _name: value:
      if ((value.dest != null) && (strings.trim value.dest != "")) then
        [
          "d ${dirOf value.dest} 0755 1000 100 -"
        ]
      else
        [ ]
    ) cfg.policyClient.policies
  );

  givcPolicyInitService = {
    description = "Initialize GIVC policies from factory or updates";
    wantedBy = [ "sysinit.target" ];
    after = [ "local-fs.target" ];
    before = [ "basic.target" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig.Type = "oneshot";
    script = concatStringsSep "\n" (
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
            chown 1000:100 "$DEST"
            chmod 0755 "$DEST"
          elif [ -f "$FACTORY" ]; then
            echo "Initializing $DEST from factory: $FACTORY"
            cp "$FACTORY" "$DEST"
            chown 1000:100 "$DEST"
            chmod 0755 "$DEST"
          else
            echo "Error! file not found:$FACTORY"
          fi

        ''
      ) startupPolicies
    );
  };

in
{
  options.ghaf.givc = {
    policyClient = {
      enable = mkEnableOption "Policy admin.";

      storePath = mkOption {
        type = types.str;
        default = "/etc/policies";
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

  config = mkIf (cfg.enable && cfg.policyClient.enable) {
    # Initialize startup policies
    systemd.services = {
      "givc-policy-init" = givcPolicyInitService;
    }
    // (mapAttrs' (
      name: p:
      nameValuePair "givc-policy-${name}" (
        mkIf (p.script != null) {
          description = "Trigger script for policy ${name}";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${p.script}";
          };
        }
      )
    ) cfg.policyClient.policies);

    # Run script in a service for each policy on update
    systemd.paths =
      (mapAttrs' (
        name: p:
        nameValuePair "givc-policy-${name}" (
          mkIf (p.script != null) {
            pathConfig.PathModified = toString p.dest;
            wantedBy = [ "multi-user.target" ];
          }
        )
      ) cfg.policyClient.policies)
      //

        # Create a path unit to trigger dependent services on policy update
        (listToAttrs (
          flatten (
            mapAttrsToList (
              name: p:
              map (dep: {
                name = "${dep}";
                value = {
                  pathConfig.PathModified = toString p.dest;
                  unitConfig.Description = "Restart ${dep} when policy ${name} changes";
                  wantedBy = [ "multi-user.target" ];
                };
              }) p.depends
            ) cfg.policyClient.policies
          )
        ));

    systemd.tmpfiles.rules = [
      "d ${cfg.policyClient.storePath} 0755 1000 100 -"
    ]
    ++ tmpFilesRules;
  };
}
