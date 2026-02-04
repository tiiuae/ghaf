# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    escapeShellArg
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.ghaf.identity.vmHostNameExport;
in
{
  _file = ./vm-hostname-export.nix;

  options.ghaf.identity.vmHostNameExport = {
    enable = mkEnableOption "export dynamic hostname to VM environment";
    hostnamePath = mkOption {
      type = types.str;
      default = "/etc/common/ghaf/hostname";
      description = "Path to hostname file in VM (usually shared via virtiofs)";
    };
  };

  config = mkIf cfg.enable {
    # Set environment via shell init
    environment.extraInit = ''
      if [ -r ${escapeShellArg cfg.hostnamePath} ]; then
        export GHAF_HOSTNAME="$(cat ${escapeShellArg cfg.hostnamePath})"
        export GHAF_HOSTNAME_FILE=${escapeShellArg cfg.hostnamePath}
      fi
    '';
  };
}
