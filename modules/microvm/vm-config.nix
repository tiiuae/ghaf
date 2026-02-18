# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# VM Configuration Module
#
# Provides ghaf.virtualization.vmConfig for resource allocation and
# profile/downstream customization.
#
# This is separate from hardware.definition which handles physical
# hardware properties. vmConfig handles:
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
          Memory balloon ratio. The VM is allocated mem * (balloonRatio + 1)
          bytes of memory, with ballooning enabled when balloonRatio > 0.
          If null, uses the default from the VM definition (typically 2).
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
    sysvms = mkOption {
      type = types.attrsOf systemVmConfigType;
      default = { };
      description = ''
        Per-system-VM configuration. Keys should match system VM names
        (e.g., guivm, netvm, audiovm, adminvm, idsvm).
      '';
      example = literalExpression ''
        {
          guivm = { mem = 16384; vcpu = 8; };
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
          chromium = { mem = 8192; extraModules = [ ./chrome.nix ]; };
          comms = { mem = 4096; };
        }
      '';
    };
  };

  # No config block - this is a pure options module
  # Consumption happens in profiles via lib.ghaf.vm.applyVmConfig
}
