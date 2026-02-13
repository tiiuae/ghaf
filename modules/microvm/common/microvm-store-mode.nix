# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Global configuration for MicroVM /nix/store mode
{
  lib,
  ...
}:
let
  inherit (lib) mkEnableOption;
in
{
  _file = ./microvm-store-mode.nix;
  options.ghaf.virtualization.microvm.storeOnDisk =
    mkEnableOption "storeOnDisk (erofs compressed image) for all MicroVMs";
}
