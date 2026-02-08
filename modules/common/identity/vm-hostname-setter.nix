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
  _file = ./vm-hostname-setter.nix;

  options.ghaf.identity.vmHostNameSetter = {
    enable = mkEnableOption "set VM hostname from shared hardware-based hostname file";
    hostnamePath = mkOption {
      type = types.str;
      default = "/etc/common/ghaf/hostname";
      description = "Path to hostname file in VM (usually shared via virtiofs)";
    };
  };

  config = mkIf cfg.enable {
    # Create writable /etc/hostname location
    systemd.tmpfiles.rules = [
      "d /etc 0755 root root - -"
    ];

    # Configure NetworkManager
    networking.networkmanager = mkIf config.networking.networkmanager.enable {
      settings = {
        main = {
          hostname-mode = "none";
        };
      };
    };

    # Set the actual hostname from the shared file
    systemd.services.set-dynamic-hostname = {
      description = "Set hostname from hardware-based identity";
      wantedBy = [ "network-pre.target" ];
      after = [
        "sysinit.target"
        "local-fs.target"
        "systemd-hostnamed.service"
      ];
      before = [
        "network-pre.target"
        "network.target"
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

                # Create /etc/hostname for NetworkManager DHCP client
                # Remove the symlink first if it exists
                rm -f /etc/hostname
                echo "$name" > /etc/hostname

                # Set kernel hostname
                echo "$name" > /proc/sys/kernel/hostname

                # Set transient and pretty hostnames via hostnamectl
                if command -v hostnamectl >/dev/null 2>&1; then
                  hostnamectl set-hostname --transient "$name" 2>/dev/null || true
                  hostnamectl set-hostname --pretty "$name" 2>/dev/null || true
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
