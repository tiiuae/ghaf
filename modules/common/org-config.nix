# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# ghaf.org - organization/deployment-specific configuration.
#
# This module is a collection of org-specific parameters that are distributed
# across the guests.
#
# The hosts ghaf.org is transported via global-config.org. Every VM receives
# global-config as the globalConfig specialArg; this module assigns the transport
# copy back into config.ghaf.org.
#
# The ghaf.org schema: every value an organization can supply. `null` is the
# "unset" marker, so an empty list or attrset means "explicitly none" and
# is forwarded as such. To add an org value, declare it as a new option and
# forward it.
{
  lib,
  ...
}@args:
let
  globalConfig = args.globalConfig or null;
in
{
  _file = ./org-config.nix;

  options.ghaf.org = lib.mkOption {
    type = lib.types.submodule {
      options = {
      };
    };
    default = { };
    description = "Organization/deployment-specific configuration.";
  };

  config = lib.mkMerge [
    (lib.mkIf (globalConfig != null) { ghaf.org = globalConfig.org; })
  ];
}
