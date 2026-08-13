# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# VM Configuration Module
#
# Provides ghaf.virtualization.vmConfig for VMM selection, resource
# allocation, and profile/downstream customization.
#
# This is separate from hardware.definition which handles physical
# hardware properties. vmConfig handles:
# - VMM selection - QEMU by default for system VMs, profile-specific system VM
#   overrides, crosvm for AppVMs, and per-VM overrides
# - Resource allocation (mem, vcpu) - varies by profile
# - Profile-specific modules (apps, services)
# - Downstream customizations
#
# Architecture:
#   hardware.definition (FIXED per device)
#   ├── Physical hardware: PCI devices, USB, input
#   └── extraModules: Hardware quirks ONLY (GPU passthrough, OVMF)
#
#   virtualization.vmConfig (VARIES by profile)
#   ├── VMM selection: default plus per-system-VM overrides
#   ├── Resource allocation: mem, vcpu
#   └── extraModules: Profile apps, services, downstream config
#
# Module Merge Order (per VM):
#   1. Base module (guivm-base.nix)                    <- mkDefault (sensible defaults)
#   2. Feature modules (desktop-features)              <- profile features
#   3. hardware.definition.guivm.extraModules          <- hardware-specific (GPU quirks)
#   4. virtualization.vmConfig.sysvms.guivm.extraModules <- profile/downstream (highest priority)
#
{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    mkOption
    types
    literalExpression
    ;

  # System VM configuration submodule (guivm, netvm, audiovm, adminvm, idsvm)
  systemVmConfigType = types.submodule {
    options = {
      vmm = mkOption {
        type = types.nullOr (
          types.enum [
            "qemu"
            "crosvm"
          ]
        );
        default = null;
        description = ''
          VMM used for this system VM.
          If null, uses ghaf.virtualization.vmConfig.defaultSysVmVmm.

          This setting takes effect when the VM's evaluated configuration
          includes lib.ghaf.vm.applyVmConfig.
        '';
        example = "crosvm";
      };

      mem = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = ''
          VM memory allocation in MB.
          If null, uses the default from the VM base module.
          This is for profile/downstream tuning, not hardware constraints.
        '';
        example = 8192;
      };

      vcpu = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = ''
          VM vCPU count.
          If null, uses the default from the VM base module.
        '';
        example = 4;
      };

      extraModules = mkOption {
        type = types.listOf types.unspecified;
        default = [ ];
        description = ''
          Additional NixOS modules for this VM.
          Used for profile-specific apps, services, and downstream customization.

          Note: Hardware-specific modules (GPU quirks, passthrough) belong in
          hardware.definition.<vm>.extraModules instead.
        '';
        example = literalExpression ''
          [
            ./my-apps.nix
            { services.myService.enable = true; }
          ]
        '';
      };
    };
  };

  # App VM configuration submodule (uses mem/vcpu for consistency with system VM definitions)
  appVmConfigType = types.submodule {
    options = {
      vmm = mkOption {
        type = types.nullOr (
          types.enum [
            "qemu"
            "crosvm"
          ]
        );
        default = null;
        description = ''
          VMM used for this App VM.
          If null, uses ghaf.virtualization.vmConfig.defaultAppVmVmm.
        '';
        example = "qemu";
      };

      mem = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "App VM memory allocation in MB.";
      };

      vcpu = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "App VM vCPU count.";
      };

      balloonRatio = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = ''
          Memory balloon ratio. The VM is allocated
          mem * (balloonRatio + 1) MB of memory, with ballooning enabled
          when balloonRatio > 0. If null, uses the default from the VM
          definition (typically 2).
        '';
      };

      extraModules = mkOption {
        type = types.listOf types.unspecified;
        default = [ ];
        description = "Additional modules for this App VM.";
      };
    };
  };
in
{
  _file = ./vm-config.nix;

  options.ghaf.virtualization.vmConfig = {
    defaultSysVmVmm = mkOption {
      type = types.enum [
        "qemu"
        "crosvm"
      ];
      default = "qemu";
      description = ''
        Default VMM for system VMs without a per-VM override.

        This setting takes effect when the VM's evaluated configuration
        includes lib.ghaf.vm.applyVmConfig. Cloud Hypervisor is intentionally
        not selectable because AdminVM does not switch root to stage 2 with it.
      '';
      example = "qemu";
    };

    defaultAppVmVmm = mkOption {
      type = types.enum [
        "qemu"
        "crosvm"
      ];
      default = "crosvm";
      description = ''
        Default VMM for App VMs without a per-VM override.
      '';
      example = "crosvm";
    };

    sysvms = mkOption {
      type = types.attrsOf systemVmConfigType;
      default = { };
      description = ''
        Per-system-VM configuration. Keys should match system VM names
        (e.g., guivm, netvm, audiovm, adminvm, idsvm).

        These settings take effect when the corresponding VM's evaluated
        configuration includes lib.ghaf.vm.applyVmConfig.
      '';
      example = literalExpression ''
        {
          guivm = { mem = 16384; vcpu = 8; };
          adminvm.vmm = "qemu"; # Optional AdminVM fallback
          netvm = { extraModules = [ ./my-net-config.nix ]; };
        }
      '';
    };

    appvms = mkOption {
      type = types.attrsOf appVmConfigType;
      default = { };
      description = ''
        Per-App-VM configuration. Keys should match App VM names.
      '';
      example = literalExpression ''
        {
          chromium = { vmm = "qemu"; mem = 8192; extraModules = [ ./chrome.nix ]; };
          comms = { mem = 4096; };
        }
      '';
    };
  };

  # Keep QEMU as the system-wide default while migrating AdminVM to crosvm.
  # Encrypted AdminVMs still need QEMU's TPM path until crosvm TPM support is
  # wired. Targets and downstream configurations can override this selection.
  config.ghaf.virtualization.vmConfig.sysvms.adminvm.vmm = lib.mkDefault (
    if config.ghaf.global-config.storage.encryption.enable then "qemu" else "crosvm"
  );
}
