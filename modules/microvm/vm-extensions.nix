# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# VM Extensions Registry
#
# This module provides a centralized registry for VM extensions.
# Modules that need to inject configuration into VMs register their
# extensions here, and VM modules consume from this registry.
#
# This replaces the extraModules pattern with a more explicit data flow.
#
# Usage:
#   # In a module that wants to extend a VM:
#   ghaf.virtualization.microvm.extensions.guivm = [ { config.foo = "bar"; } ];
#
#   # In the VM module (consumed automatically):
#   # The registry extensions are included via extendModules
#
{
  lib,
  ...
}:
let
  extensionType = lib.types.listOf (
    lib.types.oneOf [
      lib.types.attrs
      lib.types.path
      (lib.types.functionTo lib.types.attrs)
    ]
  );
in
{
  options.ghaf.virtualization.microvm.extensions = {
    guivm = lib.mkOption {
      type = extensionType;
      default = [ ];
      description = "Extensions to be applied to GUI VM configuration.";
    };

    netvm = lib.mkOption {
      type = extensionType;
      default = [ ];
      description = "Extensions to be applied to Net VM configuration.";
    };

    audiovm = lib.mkOption {
      type = extensionType;
      default = [ ];
      description = "Extensions to be applied to Audio VM configuration.";
    };

    adminvm = lib.mkOption {
      type = extensionType;
      default = [ ];
      description = "Extensions to be applied to Admin VM configuration.";
    };

    idsvm = lib.mkOption {
      type = extensionType;
      default = [ ];
      description = "Extensions to be applied to IDS VM configuration.";
    };
  };
}
