# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# System VM Registry
#
# Defines the sysvm.vms attrsOf option where each system VM module
# self-registers. This mirrors the appvm.vms pattern — the registry
# names zero VMs; each VM module contributes its own entry.
#
# Use sysvm.enabledVms for the filtered view of active VMs.
#
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.virtualization.microvm.sysvm;
in
{
  _file = ./sysvm-registry.nix;

  options.ghaf.virtualization.microvm.sysvm = {
    vms = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enable = lib.mkEnableOption "this system VM";

            vmName = lib.mkOption {
              type = lib.types.str;
              description = "VM name with hyphen (e.g., gui-vm, net-vm).";
            };

            evaluatedConfig = lib.mkOption {
              type = lib.types.nullOr lib.types.unspecified;
              default = null;
              description = "Pre-evaluated NixOS configuration for this system VM.";
            };

            extraNetworking = lib.mkOption {
              type = lib.types.networking;
              default = { };
              description = "Extra networking configuration for this system VM.";
            };
          };
        }
      );
      default = { };
      description = ''
        System VM registry. Each system VM module self-registers here.
        Keys are vmType names (guivm, netvm, etc.) matching vmConfig.sysvms keys.
        Use enabledVms for the filtered view of active VMs.
      '';
    };

    enabledVms = lib.mkOption {
      type = lib.types.attrsOf lib.types.unspecified;
      readOnly = true;
      description = ''
        Read-only attrset of enabled system VMs.
        Filtered from sysvm.vms to only include VMs with enable = true.
      '';
    };
  };

  config.ghaf.virtualization.microvm.sysvm.enabledVms = lib.filterAttrs (_: vm: vm.enable) cfg.vms;
}
