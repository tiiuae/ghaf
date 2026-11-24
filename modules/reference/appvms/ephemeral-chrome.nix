# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.reference.appvms.ephemeralChrome;
  sshAuthorizedKeys = config.ghaf.security.ssh.debug.authorizedKeys;
in
{
  _file = ./ephemeral-chrome.nix;

  options.ghaf.reference.appvms.ephemeralChrome.enable =
    lib.mkEnableOption "a manually started ephemeral Chrome AppVM";

  config = lib.mkIf (cfg.enable && config.ghaf.profiles.laptop-x86.enable or false) {
    ghaf.virtualization.microvm.guivm.applications = lib.optionals config.ghaf.givc.enable [
      {
        name = "ephemeral-browser";
        desktopName = "Ephemeral Browser";
        genericName = "Web Browser";
        description = "Disposable Chrome browser";
        categories = [
          "Network"
          "WebBrowser"
        ];
        icon = "web-browser";
        exec = "${lib.getExe' pkgs.givc-cli "givc-cli"} ${config.ghaf.givc.cliArgs} start vm ephem-vm";
      }
    ];
    ghaf.virtualization.vmConfig.appvms.ephem.vmm = "crosvm";
    ghaf.virtualization.microvm.appvm.vms.ephem = {
      enable = true;
      evaluatedConfig =
        (config.ghaf.profiles.laptop-x86.mkAppVm {
          name = "ephem";
          mem = 1536;
          vcpu = 2;
          balloonRatio = 0;
          borderColor = "#00CED1";
          vtpm.enable = false;
          persistentWaypipe.enable = false;
          packages = [ pkgs.google-chrome ];
          applications = [ ];
          extraModules = [
            {
              imports = [
                (
                  {
                    config,
                    lib,
                    pkgs,
                    modulesPath,
                    ...
                  }:
                  {
                    imports = [ (modulesPath + "/profiles/minimal.nix") ];
                    ghaf = {
                      users.admin.enable = false;
                      firewall.enable = lib.mkForce false;
                      # Keep the kernel identical to the other AppVMs.
                      firewall.kernel-modules.enable = true;
                      storagevm.enable = lib.mkForce false;
                      virtualization.microvm.swap.enable = lib.mkForce false;
                      identity.vmHostNameExport.enable = lib.mkForce false;
                      locales.enable = lib.mkForce false;
                      systemd.enable = lib.mkForce false;
                      waypipe.serverSocketPath = lib.mkForce null;
                    };
                    microvm.shares = lib.mkForce [ ];
                    microvm.optimize.enable = lib.mkForce true;
                    microvm.vsock.ssh.enable = true;
                    microvm.crosvm.extraArgs = [ "--no-usb" ];
                    hardware.graphics.enable = lib.mkForce false;
                    environment.systemPackages = lib.mkForce [
                      pkgs.google-chrome
                      pkgs.waypipe
                      pkgs.bashInteractive
                      pkgs.coreutils
                      config.systemd.package
                    ];
                    boot.kernelParams = [
                      "TERM=dumb"
                      "SYSTEMD_DEFAULT_MOUNT_RATE_LIMIT_BURST=50"
                    ];
                    system.nixos-init.enable = true;
                    system.etc.overlay.enable = true;
                    system.nssModules = lib.mkForce [ ];
                    system.nssDatabases.hosts = lib.mkForce [
                      "files"
                      "dns"
                    ];
                    nix.enable = false;
                    users.allowNoPasswordLogin = true;
                    users.users.${config.ghaf.users.appUser.name}.linger = lib.mkForce false;
                    users.users.root.openssh.authorizedKeys.keys = sshAuthorizedKeys;
                    services = {
                      dbus.enable = lib.mkForce false;
                      nscd.enable = false;
                      resolved.enable = false;
                      timesyncd.enable = false;
                      openssh = {
                        startWhenNeeded = true;
                        hostKeys = [
                          {
                            path = "/etc/ssh/ssh_host_ed25519_key";
                            type = "ed25519";
                          }
                        ];
                        settings = {
                          PasswordAuthentication = false;
                          KbdInteractiveAuthentication = false;
                          PermitRootLogin = "prohibit-password";
                        };
                      };
                    };
                    security.pam.services.sshd.startSession = lib.mkForce false;
                    security.polkit.enable = lib.mkForce false;
                    security.sudo.enable = false;
                    systemd = {
                      oomd.enable = false;
                      services.linger-users.enable = false;
                      services.systemd-logind.enable = false;
                      services.systemd-user-sessions.enable = false;
                      services."getty@".enable = false;
                      services."serial-getty@".enable = false;
                      services.chrome = {
                        wantedBy = [ "multi-user.target" ];
                        unitConfig = {
                          SuccessAction = "poweroff";
                          FailureAction = "poweroff";
                        };
                        environment.XDG_RUNTIME_DIR = "/run/chrome";
                        serviceConfig = {
                          User = config.ghaf.users.appUser.name;
                          RuntimeDirectory = "chrome";
                          RuntimeDirectoryMode = "0700";
                          ExecStart = "${lib.getExe pkgs.waypipe} --vsock -s ${
                            toString (config.ghaf.waypipe.waypipeBasePort + config.microvm.vsock.cid)
                          } --no-gpu --compress none server -- ${lib.getExe pkgs.google-chrome} --ozone-platform=wayland --disable-gpu --no-first-run --no-default-browser-check --password-store=basic";
                        };
                      };
                    };
                  }
                )
              ];
            }
          ];
        }).extendModules
          {
            specialArgs.globalConfig = lib.recursiveUpdate config.ghaf.global-config {
              givc.enable = false;
              spire.enable = false;
              storage.encryption.enable = false;
              logging.enable = false;
              theming.enable = false;
              nix.enable = false;
              debug.enable = false;
              release.enable = true;
              development.debug.tools.enable = false;
              security.audit.enable = false;
              security.ssh.debug.enable = false;
              security.ssh.release.enable = false;
            };
          };
    };
    microvm.vms.ephem-vm.autostart = lib.mkForce false;
    systemd.services."microvm@ephem-vm".serviceConfig = {
      Restart = lib.mkForce "no";
      # This disposable guest has no logind to handle the ACPI power button.
      ExecStop = lib.mkForce [
        ""
        "-${lib.getExe config.microvm.vms.ephem-vm.evaluatedConfig.config.microvm.crosvm.package} stop ephem-vm.sock"
      ];
    };
  };
}
