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

  # Get enabled VMs
  enabledVms = lib.filterAttrs (_: vm: vm.enable) cfg.vms;

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
  options.ghaf.virtualization.microvm.appvm = {
    enable = lib.mkEnableOption "appvm";

    vms = mkOption {
      description = ''
        App VM configurations. Each VM must have evaluatedConfig set via mkAppVm.
      '';
      type = types.attrsOf (
        types.submodule {
          options = {
            enable = lib.mkEnableOption "this virtual machine";

            evaluatedConfig = lib.mkOption {
              type = lib.types.unspecified;
              description = ''
                Pre-evaluated NixOS configuration for this App VM.
                Use mkAppVm from a profile to create this configuration.

                Example:
                  evaluatedConfig = config.ghaf.profiles.laptop-x86.mkAppVm {
                    name = "chromium";
                    ramMb = 6144;
                    cores = 4;
                    applications = [ ... ];
                  };
              '';
            };

            # Host-side configuration options
            # These are used by host services, not passed to VM
            name = mkOption {
              type = types.str;
              description = "Name of the App VM (without -vm suffix)";
            };

            bootPriority = mkOption {
              type = types.enum [
                "low"
                "medium"
                "high"
              ];
              description = "Boot priority for the VM (affects systemd ordering)";
              default = "low";
            };

            applications = mkOption {
              description = ''
                Applications in the AppVM (used for GUI VM launchers)
              '';
              type = types.listOf (
                types.submodule (
                  { config, lib, ... }:
                  {
                    options = {
                      name = mkOption {
                        type = types.str;
                        description = "The name of the application";
                      };
                      description = mkOption {
                        type = types.str;
                        description = "A brief description of the application";
                        default = "";
                      };
                      packages = mkOption {
                        type = types.listOf types.package;
                        description = "Packages required for the application";
                        default = [ ];
                      };
                      icon = mkOption {
                        type = types.nullOr types.str;
                        description = "Application icon";
                        default = null;
                      };
                      command = mkOption {
                        type = types.nullOr types.str;
                        description = "The command to run the application";
                        default = null;
                      };
                      extraModules = mkOption {
                        description = "Additional modules for the application";
                        type = types.listOf types.unspecified;
                        default = [ ];
                      };
                      givcName = mkOption {
                        description = "GIVC name for the application";
                        type = types.str;
                      };
                      givcArgs = mkOption {
                        description = "GIVC arguments for the application";
                        type = types.listOf types.str;
                        default = [ ];
                      };
                    };
                    config = {
                      givcName = lib.mkDefault (lib.strings.toLower (lib.replaceStrings [ " " ] [ "-" ] config.name));
                    };
                  }
                )
              );
              default = [ ];
            };

            extraNetworking = lib.mkOption {
              type = types.anything;
              description = "Extra networking options for this VM";
              default = { };
            };

            borderColor = mkOption {
              type = types.nullOr types.str;
              description = "Border color for the VM window";
              default = null;
            };

            vtpm = {
              enable = lib.mkEnableOption "vTPM support";
              runInVM = mkOption {
                type = types.bool;
                description = "Run swtpm in admin VM instead of host";
                default = false;
              };
              basePort = lib.mkOption {
                type = types.nullOr types.int;
                description = "vsock port for remote swtpm";
                default = null;
              };
            };

            usbPassthrough = mkOption {
              type = types.listOf types.anything;
              description = "USB passthrough rules for this VM";
              default = [ ];
            };
          };
        }
      );
      default = { };
    };
  };

  config =
    lib.mkIf cfg.enable {
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

      # Host services: swtpm and vsockproxy
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
    }
    # GUI VM waypipe services (x86 only with hardware.definition)
    // lib.optionalAttrs hasHardwareDefinition (
      lib.mkIf cfg.enable {
        ghaf.hardware.definition.guivm.extraModules = [
          {
            systemd.user.services = lib.mapAttrs' (name: vm: {
              name = "waypipe-${name}-vm";
              value = vm.evaluatedConfig.config.ghaf.waypipe.waypipeService;
            }) vmsWithWaypipe;
          }
        ];
      }
    );
}
