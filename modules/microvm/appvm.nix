# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# App VM Configuration Module
#
# This module handles the host-side configuration for App VMs:
# - Defines microvm.vms entries using evaluatedConfig from reference/appvms
# - Creates host swtpm services for VMs with vTPM enabled
# - Creates host vsockproxy services for VMs with waypipe
# - Passes waypipe services to GUI VM
#
# The VM-side configuration is in appvm-base.nix, created via mkAppVm in profiles.
#
# Extension Pattern:
#   ALL values (name, mem, borderColor, applications, etc.) should be defined ONLY
#   in the mkAppVm call. Host-level options automatically read from
#   evaluatedConfig.config.ghaf.appvm.vmDef. This eliminates duplication.
#
#   Features that need to extend VMs (e.g., ghaf-intro adding apps to chrome) use
#   the `extensions` option. Extensions are applied via NixOS native `extendModules`
#   to create the final evaluatedConfig.
#
{
  config,
  lib,
  pkgs,
  inputs,
  options,
  ...
}:
let
  cfg = config.ghaf.virtualization.microvm.appvm;

  # Check if hardware.definition option exists (x86 only)
  hasHardwareDefinition = options ? ghaf.hardware.definition;

  inherit (lib)
    mkOption
    types
    ;

  # Get enabled VMs with extensions applied via extendModules
  # Values are derived from the final evaluatedConfig.config.ghaf.appvm.vmDef
  enabledVmsRaw = lib.mapAttrs (
    attrName: vm:
    let
      # Apply extensions using NixOS native extendModules
      finalEvaluatedConfig =
        if vm.extensions == [ ] then
          vm.evaluatedConfig
        else
          vm.evaluatedConfig.extendModules { modules = vm.extensions; };

      vmDef = finalEvaluatedConfig.config.ghaf.appvm.vmDef or { };
    in
    vm
    // {
      # Replace evaluatedConfig with the extended version
      evaluatedConfig = finalEvaluatedConfig;
      # Derive values from vmDef - the attrset key is used as fallback for name
      name = vmDef.name or attrName;
      mem = vmDef.mem or 4096;
      balloonRatio = vmDef.balloonRatio or 2;
      borderColor = vmDef.borderColor or null;
      applications = vmDef.applications or [ ];
      vtpm = {
        enable = vmDef.vtpm.enable or false;
        runInVM = vmDef.vtpm.runInVM or false;
        basePort = vmDef.vtpm.basePort or null;
      };
    }
  ) (lib.filterAttrs (_: vm: vm.enable) cfg.vms);

  # Auto-assign vTPM basePorts for VMs using the admin-vm proxy path
  # (vtpm.enable && vtpm.runInVM). Each VM gets a unique TCP control port
  # (basePort) and data port (basePort+1) for the swtpm-proxy-shim chain.
  #
  # Ports are assigned alphabetically by VM name to be deterministic across
  # rebuilds. Adding a new VM may shift other VMs' ports, but this is safe —
  # swtpm state is persisted by VM name, not by port number.
  autoPortBase = 9100;
  autoPortStep = 10;

  vmsWithVtpmProxy = lib.filterAttrs (_: vm: vm.vtpm.enable && vm.vtpm.runInVM) enabledVmsRaw;

  sortedVtpmNames = lib.sort lib.lessThan (lib.attrNames vmsWithVtpmProxy);

  autoPortMap = lib.listToAttrs (
    lib.imap0 (i: name: {
      inherit name;
      value = autoPortBase + (i * autoPortStep);
    }) sortedVtpmNames
  );

  enabledVms = lib.mapAttrs (
    name: vm:
    if autoPortMap ? ${name} then
      vm
      // {
        vtpm = vm.vtpm // {
          basePort = autoPortMap.${name};
        };
      }
    else
      vm
  ) enabledVmsRaw;

  # Get VMs with waypipe enabled (from evaluatedConfig)
  vmsWithWaypipe = lib.filterAttrs (
    _name: vm: vm.evaluatedConfig != null && vm.evaluatedConfig.config.ghaf.waypipe.enable or false
  ) enabledVms;

  # Create microvm entry from evaluatedConfig
  makeVm =
    { vm }:
    let
      microvmBootEnabled = config.ghaf.microvm-boot.enable or false;
    in
    {
      autostart = !microvmBootEnabled;
      inherit (inputs) nixpkgs;
      inherit (vm) evaluatedConfig;
    };

  # Create host-side swtpm service for VMs with vTPM
  makeSwtpmService =
    name: vm:
    let
      swtpmScript = pkgs.writeShellApplication {
        name = "${name}-swtpm";
        runtimeInputs = with pkgs; [
          coreutils
          swtpm
        ];
        text = ''
          mkdir -p /var/lib/swtpm/${name}/state
          swtpm socket --tpmstate dir=/var/lib/swtpm/${name}/state \
            --ctrl type=unixio,path=/var/lib/swtpm/${name}/sock \
            --tpm2 \
            --log level=20
        '';
      };
    in
    lib.mkIf (vm.vtpm.enable && !vm.vtpm.runInVM) {
      enable = true;
      description = "swtpm service for ${name}";
      path = [ swtpmScript ];
      wantedBy = [ "local-fs.target" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "simple";
        Slice = "system-appvms-${name}.slice";
        User = "microvm";
        Restart = "always";
        StateDirectory = "swtpm/${name}";
        StandardOutput = "journal";
        StandardError = "journal";
        ExecStart = "${swtpmScript}/bin/${name}-swtpm";
        LogLevelMax = "notice";
      };
    };
in
{
  _file = ./appvm.nix;

  options.ghaf.virtualization.microvm.appvm = {
    enable = lib.mkEnableOption "appvm";

    # Read-only option exposing derived VM values for other modules
    enabledVms = mkOption {
      type = types.attrsOf types.unspecified;
      readOnly = true;
      description = ''
        Read-only attrset of enabled VMs with all values derived from evaluatedConfig.
        Use this instead of accessing vms directly when you need derived values
        like vtpm, applications, mem, etc.
      '';
    };

    vms = mkOption {
      description = ''
        App VM configurations. Each VM must have evaluatedConfig set via mkAppVm.

        Extension Pattern:
          - ALL values (name, mem, borderColor, applications, vtpm, etc.)
            are derived from evaluatedConfig.config.ghaf.appvm.vmDef
          - You only need to set 'enable' and 'evaluatedConfig' here
          - Use 'extensions' to add modules from external features (e.g., ghaf-intro)
          - Extensions are applied via NixOS native extendModules

        The attrset key (e.g., 'chromium' in vms.chromium) is used as fallback for name.
      '';
      type = types.attrsOf (
        types.submodule {
          options = {
            enable = lib.mkEnableOption "this virtual machine";

            evaluatedConfig = lib.mkOption {
              type = lib.types.nullOr lib.types.unspecified;
              default = null;
              description = "Base NixOS configuration from mkAppVm profile function.";
            };

            extensions = lib.mkOption {
              type = types.listOf types.deferredModule;
              default = [ ];
              description = ''
                Additional modules to extend this VM's configuration.
                Applied via NixOS native extendModules after the base evaluatedConfig.
                Use this for features that need to add apps, services, or other
                configuration to a VM without modifying its base definition.
              '';
              example = lib.literalExpression ''
                [
                  ({ pkgs, ... }: {
                    ghaf.appvm.applications = [{
                      name = "My App";
                      command = "myapp";
                      packages = [ pkgs.myapp ];
                    }];
                  })
                ]
              '';
            };

            # Host-specific options (not derived from vmDef)

            extraNetworking = lib.mkOption {
              type = types.anything;
              description = "Extra networking options for this VM (host-side only)";
              default = { };
            };

            usbPassthrough = mkOption {
              type = types.listOf types.anything;
              description = "USB passthrough rules for this VM (host-side only)";
              default = [ ];
            };

            bootPriority = mkOption {
              type = types.enum [
                "low"
                "medium"
                "high"
              ];
              description = "Boot priority for the VM (affects systemd ordering)";
              default = "medium";
            };
          };
        }
      );
      default = { };
    };
  };

  config = lib.mkMerge [
    # Always expose enabledVms (even if appvm.enable = false, it will be empty)
    {
      ghaf.virtualization.microvm.appvm.enabledVms = enabledVms;
    }

    # Main App VM configuration
    (lib.mkIf cfg.enable {
      # Assertions - each enabled VM must have evaluatedConfig
      assertions = lib.mapAttrsToList (name: vm: {
        assertion = vm.evaluatedConfig != null;
        message = "appvm.vms.${name}.evaluatedConfig must be set. Use mkAppVm from a profile.";
      }) enabledVms;

      # Define microvms for each AppVM
      microvm.vms =
        let
          vmEntries = lib.attrsets.mapAttrsToList (name: vm: { inherit name; } // vm) enabledVms;
          vmConfigs = map (vm: { "${vm.name}-vm" = makeVm { inherit vm; }; }) vmEntries;
        in
        lib.foldr lib.recursiveUpdate { } vmConfigs;

      # Host-side swtpm and vsockproxy services
      systemd.services =
        let
          # swtpm services for VMs with vTPM on host
          swtpms = lib.mapAttrsToList (name: vm: {
            "${name}-vm-swtpm" = makeSwtpmService name vm;
          }) enabledVms;

          # vsockproxy services for VMs with waypipe
          proxyServices = lib.mapAttrsToList (name: vm: {
            "vsockproxy-${name}-vm" = vm.evaluatedConfig.config.ghaf.waypipe.proxyService;
          }) vmsWithWaypipe;
        in
        lib.foldr lib.recursiveUpdate { } (swtpms ++ proxyServices);

      # Extra networking hosts
      ghaf.common.extraNetworking.hosts = lib.mapAttrs' (name: vm: {
        name = "${name}-vm";
        value = vm.extraNetworking or { };
      }) enabledVms;

      # USB passthrough rules
      ghaf.hardware.passthrough.vhotplug.usbRules = lib.concatMap (vm: vm.usbPassthrough) (
        lib.attrValues enabledVms
      );
    })

    # GUI VM waypipe services (x86 only with hardware.definition)
    (lib.mkIf (cfg.enable && hasHardwareDefinition) {
      ghaf.hardware.definition.guivm.extraModules = [
        {
          systemd.user.services = lib.mapAttrs' (name: vm: {
            name = "waypipe-${name}-vm";
            value = vm.evaluatedConfig.config.ghaf.waypipe.waypipeService;
          }) vmsWithWaypipe;
        }
      ];
    })
  ];
}
