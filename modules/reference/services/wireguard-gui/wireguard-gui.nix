# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.ghaf.reference.services.wireguard-gui;
  hasStorageVm = (lib.hasAttr "storagevm" config.ghaf) && config.ghaf.storagevm.enable;
  wg_app_dir = "/etc/wireguard";
  docUrl = "https://ghaf.tii.ae/ghaf/dev/ref/wireguard-gui/";
  debugFlag = lib.optionalString config.ghaf.profiles.debug.enable "--log-level TRACE";
  wireguard-gui-launcher = pkgs.writeShellScriptBin "wireguard-gui-launcher" ''
    PATH=/run/wrappers/bin:/run/current-system/sw/bin
    ${pkgs.wireguard-gui}/bin/wireguard-gui \
      --app-dir ${wg_app_dir} \
      --config-owner ${config.ghaf.users.appUser.name} \
      --config-owner-group ${config.ghaf.users.appUser.name} \
      --doc-url ${docUrl} \
      ${debugFlag}
  '';
  scriptsDir = builtins.path {
    path = ./scripts;
    name = "wg-scripts";
  };

in
{
  options.ghaf.reference.services.wireguard-gui = {
    enable = lib.mkEnableOption "Enable the Wireguard GUI service";
    serverPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "Wireguard server ports";
    };
  };

  config = lib.mkIf cfg.enable {

    ghaf.storagevm =
      (config.ghaf.storagevm or { })
      // lib.mkIf hasStorageVm {
        directories = [
          {
            directory = "${wg_app_dir}";
            mode = "0600";
          }
          {
            directory = "${wg_app_dir}/configs";
            mode = "0600";
          }
        ];
      };
    systemd.tmpfiles.rules = [
      # Create directory owned by appUser
      "d /etc/wireguard/scripts 0644 ${config.ghaf.users.appUser.name} ${config.ghaf.users.appUser.name} -"

      # Symlink scripts from Nix store
      "L /etc/wireguard/scripts/client_full_vpn - - - - ${scriptsDir}/client_full_vpn"
    ]
    ++ lib.optionals (cfg.serverPorts != [ ]) [
      # Only include this when serverPorts is NOT empty
      "L /etc/wireguard/scripts/server - - - - ${scriptsDir}/server"
    ];

    ghaf.givc.appvm.applications = [
      {
        name = "wireguard-gui";
        command = "${config.ghaf.givc.appPrefix}/run-waypipe ${wireguard-gui-launcher}/bin/wireguard-gui-launcher";
      }
    ];

    ghaf.firewall.allowedUDPPorts = cfg.serverPorts;

    environment.systemPackages = lib.optionals config.ghaf.profiles.debug.enable [
      pkgs.wireguard-tools
    ];
    security.polkit = {
      enable = true;
      debug = true;
      extraConfig = ''
        polkit.addRule(function(action, subject) {
          polkit.log("user " +  subject.user + " is attempting action " + action.id + " from PID " + subject.pid);
          polkit.log("subject = " + subject);
          polkit.log("action = " + action);
          polkit.log("actioncmdline = " + action.lookup("command_line"));
        });
        polkit.addRule(function(action, subject) {
          var expectedcmdline = "XDG_RUNTIME_DIR=/run/user/1000 " +
                              "XDG_DATA_DIRS=" +
                              "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}:" +
                              "${pkgs.gtk4}/share/gsettings-schemas/${pkgs.gtk4.name}:" +
                              "/home/appuser/.nix-profile/share:" +
                              "/nix/profile/share:" +
                              "/home/appuser/.local/state/nix/profile/share:" +
                              "/etc/profiles/per-user/appuser/share:" +
                              "/nix/var/nix/profiles/default/share:" +
                              "/run/current-system/sw/share " +
                              "PATH=/run/wrappers/bin:/run/current-system/sw/bin " +
                              "LIBGL_ALWAYS_SOFTWARE=true " +
                              "${pkgs.wireguard-gui}/bin/.wireguard-gui-wrapped --config-owner ${config.ghaf.users.appUser.name} --config-owner-group users";
          polkit.log("Expected commandline = " + expectedcmdline);
          if (action.id == "org.freedesktop.policykit.exec" &&
            RegExp('^/run/current-system/sw/bin/env WAYLAND_DISPLAY=wayland-([a-zA-Z0-9]){10} $').test(action.lookup("command_line").slice(0,66)) === true &&
            subject.user == "${config.ghaf.users.appUser.name}") {
          return polkit.Result.YES;
            }
        });
      '';
    };

  };
}
