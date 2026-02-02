# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# GUI VM Host Module - Uses evaluatedConfig for composition
#
# Key features:
# - Common host bindings via mkCommonHostBindings (truly DRY - only vmName + tpmIndex)
# - Consumes hardware passthrough config from options (no extraModules)
# - Hardware features controlled by OPTIONS (fprint, yubikey, brightness)
# - Downstream extends via extendModules on exported vmConfigs
#
{
  config,
  lib,
  pkgs,
  self,
  inputs,
  ...
}:
let
  vmName = "gui-vm";
  cfg = config.ghaf.virtualization.microvm.guivm;

  inherit (lib) hasAttrByPath optionalAttrs optionals;
  inherit (pkgs.stdenv.hostPlatform) isx86;

  fullVirtualization = isx86 && (hasAttrByPath [ "hardware" "devices" ] config.ghaf);

  mkGuiVm = self.lib.vmBuilders.mkGuiVm { inherit inputs lib; };
  enabledVms = lib.filterAttrs (_: vm: vm.enable) config.ghaf.virtualization.microvm.appvm.vms;
  sharedSystemConfigBase = config._module.specialArgs.sharedSystemConfig or { };

  # Extend sharedSystemConfig with GUI-specific settings (GIVC)
  systemConfigModule = sharedSystemConfigBase // {
    ghaf = (sharedSystemConfigBase.ghaf or { }) // {
      givc = {
        inherit (config.ghaf.givc) enable;
        enableTls = lib.mkDefault (config.ghaf.givc.enableTls or false);
      };
    };
  };

  baseGuiVm = mkGuiVm {
    inherit (config.nixpkgs.hostPlatform) system;
    inherit systemConfigModule;
  };

  # Build virtual launchers for apps running in AppVMs
  virtualApps = lib.lists.concatMap (
    vm: map (app: app // { vmName = "${vm.name}-vm"; }) vm.applications
  ) (lib.attrValues (lib.mapAttrs (name: vm: vm // { inherit name; }) enabledVms));

  virtualLaunchers = map (app: rec {
    inherit (app) name description;
    vm = app.vmName;
    execPath = "${pkgs.givc-cli}/bin/givc-cli ${config.ghaf.givc.cliArgs} start app --vm ${vm} ${app.givcName}";
    inherit (app) icon;
  }) virtualApps;

  guivmLaunchers = map (app: {
    inherit (app) name description;
    execPath = app.command;
    inherit (app) icon;
  }) cfg.applications;

  waypipeUid =
    if config.ghaf.users.homedUser.enable or false then
      toString (config.ghaf.users.homedUser.uid or 1000)
    else
      toString (config.ghaf.users.admin.uid or 1000);
  waypipePubDir =
    config.ghaf.security.sshKeys.waypipeSshPublicKeyDir or "/run/waypipe-ssh-public-key";

  # === Common Host Bindings (TRULY DRY) ===
  commonHostBindings = self.lib.mkCommonHostBindings config {
    inherit vmName;
    tpmIndex = "0x81703000";
  };

  # === GUI-VM Specific Bindings ===
  guiVmSpecificBindings =
    { pkgs, lib, ... }:
    let
      keygenScript = pkgs.writeShellScriptBin "waypipe-ssh-keygen" ''
        set -xeuo pipefail
        mkdir -p /run/waypipe-ssh
        mkdir -p ${waypipePubDir}
        echo -en "\n\n\n" | ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f /run/waypipe-ssh/id_ed25519 -C ""
        chown ${waypipeUid}:users /run/waypipe-ssh/*
        cp /run/waypipe-ssh/id_ed25519.pub ${waypipePubDir}/id_ed25519.pub
        chown -R ${waypipeUid}:users ${waypipePubDir}
      '';
    in
    {
      ghaf.development.debug.tools.gui.enable = lib.mkDefault config.ghaf.development.debug.tools.enable;

      ghaf.users = {
        adUsers.enable = config.ghaf.users.profile.ad-users.enable or false;
        homedUser = {
          enable = config.ghaf.users.profile.homed-user.enable or false;
          fidoAuth = true;
        };
      };

      ghaf.graphics = {
        launchers = guivmLaunchers ++ lib.optionals config.ghaf.givc.enable virtualLaunchers;
        cosmic.securityContext.rules =
          map
            (vm: {
              identifier = vm.name;
              color = vm.borderColor;
            })
            (
              lib.attrValues (
                lib.mapAttrs (name: vm: {
                  inherit name;
                  inherit (vm) borderColor;
                }) enabledVms
              )
            );
      };

      environment.sessionVariables = lib.optionalAttrs config.ghaf.profiles.debug.enable (
        {
          GIVC_NAME = "admin-vm";
          GIVC_ADDR = config.ghaf.networking.hosts."admin-vm".ipv4 or "192.168.101.10";
          GIVC_PORT = "9001";
        }
        // lib.optionalAttrs (config.ghaf.givc.enableTls or false) {
          GIVC_CA_CERT = "/run/givc/ca-cert.pem";
          GIVC_HOST_CERT = "/run/givc/cert.pem";
          GIVC_HOST_KEY = "/run/givc/key.pem";
        }
      );

      systemd.services."waypipe-ssh-keygen" = {
        enable = true;
        description = "Generate SSH keys for Waypipe";
        path = [ keygenScript ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          StandardOutput = "journal";
          StandardError = "journal";
          ExecStart = "${keygenScript}/bin/waypipe-ssh-keygen";
        };
      };
    };

  # Hardware passthrough modules - features controlled by OPTIONS
  hardwareModules = optionals fullVirtualization [
    (optionalAttrs (hasAttrByPath [
      "ghaf"
      "hardware"
      "devices"
      "gpus"
    ] config) config.ghaf.hardware.devices.gpus)
    (optionalAttrs (hasAttrByPath [
      "ghaf"
      "hardware"
      "devices"
      "evdev"
    ] config) config.ghaf.hardware.devices.evdev)
    (optionalAttrs (hasAttrByPath [ "ghaf" "kernel" "guivm" ] config) config.ghaf.kernel.guivm)
    { config.ghaf.services.firmware.enable = true; }
    (optionalAttrs (hasAttrByPath [ "ghaf" "qemu" "guivm" ] config) config.ghaf.qemu.guivm)
    # Feature OPTIONS - not hardcoded
    (optionalAttrs cfg.fprint { config.ghaf.services.fprint.enable = true; })
    (optionalAttrs cfg.yubikey { config.ghaf.services.yubikey.enable = true; })
    (optionalAttrs cfg.brightness { config.ghaf.services.brightness.enable = true; })
  ];

  commonModule = {
    config.ghaf = { inherit (config.ghaf) common; };
  };

  # === Extensions from Registry ===
  registryExtensions = config.ghaf.virtualization.microvm.extensions.guivm or [ ];
in
{
  options.ghaf.virtualization.microvm.guivm = {
    enable = lib.mkEnableOption "GUIVM";

    # Hardware feature OPTIONS
    fprint = lib.mkOption {
      type = lib.types.bool;
      default = isx86 && cfg.enable;
      description = "Enable fingerprint reader passthrough to GUIVM.";
    };

    yubikey = lib.mkOption {
      type = lib.types.bool;
      default = isx86 && cfg.enable;
      description = "Enable YubiKey passthrough to GUIVM.";
    };

    brightness = lib.mkOption {
      type = lib.types.bool;
      default = isx86 && cfg.enable;
      description = "Enable brightness control passthrough to GUIVM.";
    };

    extraNetworking = lib.mkOption {
      type = lib.types.networking;
      description = "Extra Networking option";
      default = { };
    };

    applications = lib.mkOption {
      description = "Applications to include in the GUIVM";
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "The name of the application";
            };
            description = lib.mkOption {
              type = lib.types.str;
              description = "A brief description of the application";
            };
            icon = lib.mkOption {
              type = lib.types.str;
              description = "Application icon";
              default = null;
            };
            command = lib.mkOption {
              type = lib.types.str;
              description = "The command to run the application";
              default = null;
            };
          };
        }
      );
      default = [ ];
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = sharedSystemConfigBase != { };
        message = "GUIVM requires sharedSystemConfig to be provided via specialArgs.";
      }
    ];

    ghaf.common.extraNetworking.hosts.${vmName} = cfg.extraNetworking;

    microvm.vms.${vmName} = {
      autostart = !config.ghaf.microvm-boot.enable;

      evaluatedConfig = baseGuiVm.extendModules {
        modules = [
          commonHostBindings
          guiVmSpecificBindings
          commonModule
        ]
        ++ hardwareModules
        ++ registryExtensions;
      };
    };
  };
}
