# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Global configuration for MicroVM /nix/store mode
{
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
in
{
  _file = ./microvm-store-mode.nix;
  options.ghaf.virtualization.microvm.storeOnDisk = mkOption {
    type = types.bool;
    default = false;
    description = ''
      Global setting for all MicroVMs: use storeOnDisk (erofs compressed image)
      instead of shared virtiofs /nix/store.

      When true:  All VMs use storeOnDisk (compressed, less memory)
      When false: All VMs use sharedStore (virtiofs, more memory)

      Default is false (shared store for easier development experience).

      This setting is read by MicroVMs via configHost.ghaf.virtualization.microvm.storeOnDisk
      to configure their /nix/store access method.
    '';
  };
}
