# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
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

  cfg = config.ghaf.identity.vmHostNameSetter;
in
{
  options.ghaf.identity.vmHostNameSetter = {
    enable = mkEnableOption "set VM hostname from shared hardware-based hostname file";
    hostnamePath = mkOption {
      type = types.str;
      default = "/etc/common/ghaf/hostname";
      description = "Path to hostname file in VM (usually shared via virtiofs)";
    };
  };

  config = mkIf cfg.enable {
    # Configure NetworkManager to not override the hostname
    networking.networkmanager.settings = mkIf config.networking.networkmanager.enable {
      main = {
        hostname-mode = "none";
      };
    };

    # Set the actual hostname from the shared file
    systemd.services.set-dynamic-hostname = {
      description = "Set hostname from hardware-based identity";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      before = [
        "network-pre.target"
        "NetworkManager.service"
      ];
      serviceConfig =
        let
          setDynamicHostname = pkgs.writeShellApplication {
            name = "set-dynamic-hostname";
            runtimeInputs = [
              pkgs.systemd
              pkgs.coreutils
            ];
            text = ''
              if [ -r ${escapeShellArg cfg.hostnamePath} ]; then
                name=$(cat ${escapeShellArg cfg.hostnamePath})

                # Set transient hostname
                if command -v hostnamectl >/dev/null 2>&1; then
                  hostnamectl --transient set-hostname "$name" 2>/dev/null || true
                  hostnamectl set-hostname --pretty "$name" 2>/dev/null || true
                fi

                # Also try direct kernel method as fallback
                if [ -w /proc/sys/kernel/hostname ]; then
                  echo "$name" > /proc/sys/kernel/hostname 2>/dev/null || true
                fi
              fi
            '';
          };
        in
        {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${setDynamicHostname}/bin/set-dynamic-hostname";
        };
    };
  };
}
