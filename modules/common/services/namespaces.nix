# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ config, lib, ... }:
let
  inherit (builtins) attrNames hasAttr;
  inherit (lib) mkOption types optionalAttrs;
in
{
  options.ghaf.namespaces = {
    vms = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of VMs currently enabled.";
    };
  };
  config = {
    ghaf = optionalAttrs (hasAttr "microvm" config) {
      namespaces = optionalAttrs (hasAttr "vms" config.microvm) { vms = attrNames config.microvm.vms; };
    };
  };
}
