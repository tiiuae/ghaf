# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  cfg = config.ghaf.identity.vmHostNameExport;
in
{
  options.ghaf.identity.vmHostNameExport = {
    enable = lib.mkEnableOption "Export dynamic hostname to VM environment";
    hostnamePath = lib.mkOption {
      type = lib.types.str;
      default = "/etc/common/ghaf/hostname";
      description = "Path to hostname file in VM (usually shared via virtiofs)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Set environment via shell init
    environment.extraInit = ''
      if [ -r ${lib.escapeShellArg cfg.hostnamePath} ]; then
        export GHAF_HOSTNAME="$(cat ${lib.escapeShellArg cfg.hostnamePath})"
        export GHAF_HOSTNAME_FILE=${lib.escapeShellArg cfg.hostnamePath}
      fi
    '';
  };
}
