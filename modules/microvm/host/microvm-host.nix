# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# MicroVM Host Configuration Module
#
# Note: `inputs` is received via specialArgs from mkLaptopConfiguration,
# eliminating the need for the `{ inputs }:` wrapper pattern.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.ghaf.virtualization.microvm-host;
  inherit (lib)
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    types
    ;
  userConfig =
    if (lib.hasAttr "gui-vm" config.microvm.vms) then
      let
        vmConfig = lib.ghaf.vm.getConfig config.microvm.vms.gui-vm;
      in
      if vmConfig != null then vmConfig.ghaf.users else config.ghaf.users
    else
      config.ghaf.users;
  hasLoginUser = userConfig.homedUser.enable || userConfig.adUsers.enable;
  loginUserHasDynamicUid = userConfig.adUsers.enable;
  loginUserUid = toString (userConfig.homedUser.uid or 1000);
  loginUserSessionDir = "/run/ghaf/session";
  loginUserUidFile = "${loginUserSessionDir}/gui-vm-user.uid";
  sharedVmDirectoryPaths = [
    "/persist/storagevm/shared/shares"
  ]
  ++ map (n: "/persist/storagevm/shared/shares/Unsafe ${n} share/") cfg.sharedVmDirectory.vms;
  xdgRuleFor =
    xdgPath:
    if loginUserHasDynamicUid then
      # AD users keep their directory service UID, so the handoff path cannot be pre-owned by a fixed local user.
      "D ${xdgPath} 0733 root root -"
    else
      "D ${xdgPath} 0700 ${loginUserUid} users -";
  sharedDirRuleFor =
    path:
    if loginUserHasDynamicUid then
      # AD logins need host directories that AppVMs can access before the active GUI UID is known.
      "d ${path} 0770 root users"
    else
      "d ${path} 0760 ${loginUserUid} users";
  hasAudioVmAcpiPath =
    (lib.hasAttr "audio-vm" config.microvm.vms)
    && (config.ghaf.hardware.definition.audio.acpiPath != null);
in
{
  _file = ./microvm-host.nix;

  imports = [
    inputs.microvm.nixosModules.host
    inputs.self.nixosModules.givc
    inputs.self.nixosModules.hardware-x86_64-host-kernel
    inputs.self.nixosModules.mem-manager
    ./networking.nix
    ./shared-mem.nix
    ./boot.nix
    ./vtpm-proxy.nix
  ];

  options.ghaf.virtualization.microvm-host = {
    enable = mkEnableOption "MicroVM Host";
    networkSupport = mkEnableOption "Network support services to run host applications.";
    extraNetworking = lib.mkOption {
      type = types.networking;
      description = "Extra Networking option";
      default = { };
    };
    sharedVmDirectory = {
      enable = mkEnableOption "shared directory" // {
        default = true;
      };

      vms = mkOption {
        description = ''
          List of names of virtual machines for which unsafe shared directory will be enabled.
        '';
        type = types.listOf types.str;
        default = [ ];
      };

      inotifyPassthrough = mkEnableOption "inotify passthrough" // {
        default = true;
      };

    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      microvm.host.enable = true;
      # microvm.host.useNotifySockets = true;

      ghaf = {
        type = "host";
        microvm-boot = {
          inherit (config.ghaf.virtualization.microvm.guivm) enable;
          debug = config.ghaf.profiles.debug.enable;
        };
        systemd = {
          withName = "host-systemd";
          enable = true;
          withPolkit = true;
          withTpm2Tss = pkgs.stdenv.hostPlatform.isx86;
          withRepart = true;
          withFido2 = true;
          withCryptsetup = true;
          withLocaled = true;
          withTimesyncd = cfg.networkSupport;
          withNss = cfg.networkSupport;
          withResolved = cfg.networkSupport;
          withSerial = config.ghaf.profiles.debug.enable;
          withDebug = config.ghaf.profiles.debug.enable;
          withHardenedConfigs = true;
        };
        givc.host.enable = true;
        graphics.boot = {
          enable = true; # Enable graphical boot on host
          renderer = "simpledrm"; # Force simpledrm framebuffer for graphical boot on host
        };
        services = {
          power-manager = {
            host.enable = true;
            gui.enable = config.ghaf.profiles.graphics.enable;
          };
          performance = {
            host.enable = true;
            gui.enable = config.ghaf.profiles.graphics.enable;
          };
          create-fake-battery.enable = true;
          firmware.enable = true;

          # Monitoring of /nix/store for nixos-rebuild copy sessions and flagging interruptions
          storeWatcher.enable = false;
        };
        development = {
          nix-setup.automatic-gc.enable = config.ghaf.development.nix-setup.enable;
          debug.tools.host.enable = config.ghaf.development.debug.tools.enable;
          # Serial console is only meaningful on the host
          usb-serial.enable = config.ghaf.profiles.debug.enable;
        };
        logging = {
          listener = {
            address = lib.mkDefault config.ghaf.global-config.logging.listener.address;
            port = lib.mkDefault config.ghaf.global-config.logging.listener.port;
          };
          journalClient = {
            inherit (config.ghaf.logging) enable;
          };
        };
        common = {
          extraNetworking.hosts.ghaf-host = cfg.extraNetworking;
          policies = lib.mkIf config.ghaf.givc.policyClient.enable {
            ghaf-host = config.ghaf.givc.policyClient.policies;
          };
          spire.agents = lib.mkIf config.ghaf.security.spire.agent.enable {
            ghaf-host = {
              inherit (config.ghaf.security.spire.agent) nodeAttestationMode workloads;
            };
          };
        };

        security.spire.agent = {
          inherit (config.ghaf.global-config.spire) enable;
          logLevel = if config.ghaf.global-config.spire.debug then "DEBUG" else "INFO";
          nodeAttestationMode = if config.ghaf.global-config.givc.enable then "x509pop" else "join_token";
          settings.join_token.token = "/persist/common/spire/tokens/${config.networking.hostName}.token";
          trustBundlePath = "/persist/common/spire/bundle.pem";
        };
      };

      # Create required host directories
      systemd.tmpfiles.rules =
        let
          vmsWithXdg = lib.filter (
            vm:
            let
              vmConfig = lib.ghaf.vm.getConfig vm;
              # Safe check for xdgitems.enable - avoid triggering option evaluation
              hasXdgEnabled =
                vmConfig != null
                && lib.hasAttr "ghaf" vmConfig
                && lib.hasAttr "xdgitems" vmConfig.ghaf
                && lib.hasAttr "enable" vmConfig.ghaf.xdgitems
                && vmConfig.ghaf.xdgitems.enable;
            in
            hasXdgEnabled
          ) (builtins.attrValues config.microvm.vms);
          xdgDirs = lib.flatten (
            map (
              vm:
              let
                vmConfig = lib.ghaf.vm.getConfig vm;
                # Safe access to xdgHostPaths - readOnly option that may not be set
                # Use tryEval to handle the case where option has no value
                xdgPathsAttempt = builtins.tryEval (vmConfig.ghaf.xdgitems.xdgHostPaths or [ ]);
              in
              if xdgPathsAttempt.success then xdgPathsAttempt.value else [ ]
            ) vmsWithXdg
          );
          xdgRules = map xdgRuleFor xdgDirs;
        in
        [
          "d /persist/common 0755 root root -"
          "d /persist/common/ghaf 0755 root root -"
          "d /persist/sysupdate 0755 root root -"
          "d /persist/storagevm 0755 root root -"
          "d /persist/storagevm/img 0700 microvm kvm -"
          "f /tmp/cancel 0770 microvm kvm -"
        ]
        ++ lib.optionals config.ghaf.givc.enable [
          "d /persist/storagevm/givc 0700 microvm kvm -"
        ]
        ++ lib.optionals hasLoginUser [
          "d /persist/storagevm/homes 0700 microvm kvm -"
        ]
        # Allow permission to microvm user to read ACPI tables of soundcard mic array
        ++ lib.optionals hasAudioVmAcpiPath [
          "f ${config.ghaf.hardware.definition.audio.acpiPath} 0400 microvm kvm -"
        ]
        ++ xdgRules;

      systemd.services =
        let
          vmsWithEncryptedStorage = lib.filterAttrs (
            _name: vm:
            let
              vmConfig = lib.ghaf.vm.getConfig vm;
            in
            vmConfig != null
            && lib.hasAttr "storagevm" vmConfig.ghaf
            && vmConfig.ghaf.storagevm.encryption.enable
          ) config.microvm.vms;

          vmstorageSetupServices = lib.foldl' (
            result: name:
            result
            // {
              "format-microvm-storage-${name}" =
                let
                  vmConfig = lib.ghaf.vm.getConfig config.microvm.vms.${name};
                  cfg = vmConfig.ghaf.storagevm;

                  hostImage = "/persist/storagevm/img/${cfg.name}.img";

                  formatStorageScript = pkgs.writeShellApplication {
                    name = "format-microvm-storage-${name}-script";
                    runtimeInputs = with pkgs; [
                      util-linux
                      qemu-utils
                      cryptsetup
                      e2fsprogs
                    ];
                    text = ''
                      set -x
                      qemu-img create ${hostImage} ${toString cfg.encryption.initialDiskSize}M
                      # Reduce KDF memory and time cost because VMs have limited resources
                      # This keyslot will be wiped later once TPM is enrolled
                      cryptsetup luksFormat -q \
                        --disable-keyring \
                        --luks2-keyslots-size 1M \
                        --pbkdf-force-iterations 4 \
                        --pbkdf-memory 50000 \
                        "${hostImage}" <<< ""
                      cryptsetup open -q --disable-keyring "${hostImage}" "${name}-data" <<< ""
                      mkfs.ext4 -D "/dev/mapper/${name}-data"
                      cryptsetup close "${name}-data"
                      chown microvm:kvm ${hostImage}
                      chmod 0700 ${hostImage}
                    '';
                  };
                in
                {
                  description = "Format MicroVM storage image '${name}'";
                  before = [
                    "microvm@${name}.service"
                  ];
                  partOf = [ "microvm@${name}.service" ];
                  wantedBy = [ "microvms.target" ];
                  unitConfig.ConditionPathExists = "!${hostImage}";
                  serviceConfig.Type = "oneshot";
                  serviceConfig.ExecStart = lib.getExe formatStorageScript;
                };
            }
          ) { } (lib.attrNames vmsWithEncryptedStorage);
        in
        {
          # Device-id and machine-id generation moved to ghaf.identity.dynamicHostName module
        }
        // vmstorageSetupServices;
    }
    (mkIf cfg.sharedVmDirectory.enable {
      # Create directories required for sharing files with correct permissions.
      systemd.tmpfiles.rules =
        let
          vmDirs = map (
            n: sharedDirRuleFor "/persist/storagevm/shared/shares/Unsafe\\x20${n}\\x20share/"
          ) cfg.sharedVmDirectory.vms;
        in
        [
          "d /persist/storagevm/shared 0755 root root"
          (sharedDirRuleFor "/persist/storagevm/shared/shares")
        ]
        ++ vmDirs;
    })
    (mkIf (cfg.sharedVmDirectory.enable && loginUserHasDynamicUid) {
      systemd.tmpfiles.rules = [
        "d /run/ghaf 0755 root root -"
        "d /run/ghaf/session 0750 root root -"
      ];

      systemd.services."shared-vm-directory-acl" =
        let
          aclSetupScript = pkgs.writeShellApplication {
            name = "shared-vm-directory-acl";
            runtimeInputs = with pkgs; [
              acl
              coreutils
              findutils
            ];
            text = ''
              set -euo pipefail

              uid_file=${lib.escapeShellArg loginUserUidFile}
              current_uid=""

              if [ -r "$uid_file" ]; then
                current_uid="$(tr -d '[:space:]' < "$uid_file")"
                case "$current_uid" in
                  ""|*[!0-9]*)
                    echo "Ignoring invalid GUI VM login UID: '$current_uid'" >&2
                    current_uid=""
                    ;;
                esac
              fi

              apply_shared_acl() {
                local path="$1"

                install -d -m 0770 -o root -g users "$path"
                chmod 0770 "$path"
                chgrp users "$path"
                setfacl -Rb "$path"
                setfacl -R -m "g:users:rwX,o::---" "$path"
                find "$path" -type d -exec setfacl -m "g:users:rwx,o::---,d:g:users:rwx,d:o::---" '{}' +

                if [ -n "$current_uid" ]; then
                  setfacl -R -m "u:$current_uid:rwX,g:users:rwX,o::---" "$path"
                  find "$path" -type d -exec setfacl -m "u:$current_uid:rwx,g:users:rwx,o::---,d:u:$current_uid:rwx,d:g:users:rwx,d:o::---" '{}' +
                fi
              }

              for path in ${lib.concatMapStringsSep " " lib.escapeShellArg sharedVmDirectoryPaths}; do
                apply_shared_acl "$path"
              done
            '';
          };
        in
        {
          enable = true;
          description = "Apply shared folder ACLs for the active GUI login";
          wantedBy = [ "multi-user.target" ];
          after = [ "local-fs.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe aclSetupScript;
          };
        };

      systemd.paths."shared-vm-directory-acl" = {
        description = "Watch GUI login UID handoff and refresh shared folder ACLs";
        wantedBy = [ "multi-user.target" ];
        wants = [ "shared-vm-directory-acl.service" ];
        pathConfig = {
          PathChanged = loginUserSessionDir;
          Unit = "shared-vm-directory-acl.service";
        };
      };
    })
    (mkIf
      (
        cfg.sharedVmDirectory.enable
        && cfg.sharedVmDirectory.inotifyPassthrough
        && config.ghaf.virtualization.microvm.guivm.enable
      )
      {
        # Enable passthrough of the shared directory inotify events from the host to the GUI VM
        # This is required for the file manager to refresh the shared directory content when it is updated from AppVMs
        systemd.services.vinotify = {
          enable = true;
          description = "vinotify";
          wantedBy = [ "multi-user.target" ];
          before = [ "multi-user.target" ];
          serviceConfig = {
            Type = "simple";
            Restart = "always";
            RestartSec = "1";
            ExecStart = "${pkgs.vinotify}/bin/vinotify --cid ${toString config.ghaf.networking.hosts.gui-vm.cid} --port 2000 --path /persist/storagevm/shared/shares --mode host";
          };
          startLimitIntervalSec = 0;
        };

        # Shared directories guest config is now provided by guivm-desktop-features module
        # See: modules/desktop/guivm/shared-directories.nix
      }
    )
    (mkIf config.services.userborn.enable {
      system.activationScripts.microvm-host = lib.mkForce "";
      systemd.services."microvm-host-startup" =
        let
          microVmStartupScript = pkgs.writeShellApplication {
            name = "microvm-host-startup";
            runtimeInputs = [
              pkgs.coreutils
            ];
            text = ''
              mkdir -p ${config.microvm.stateDir}
              chown microvm:kvm ${config.microvm.stateDir}
              chmod g+w ${config.microvm.stateDir}
            '';
          };
        in
        {
          enable = true;
          description = "MicroVM host startup service";
          wantedBy = [ "userborn.service" ];
          after = [ "userborn.service" ];
          unitConfig.ConditionPathExists = "!${config.microvm.stateDir}";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${microVmStartupScript}/bin/microvm-host-startup";
          };
        };
    })
    {
      systemd.services."nvidia-brightness-control" =
        let
          backlightDevice = "nvidia_wmi_ec_backlight";
          controlBrightnessScript = pkgs.writeShellApplication {
            name = "nvidia-brightness-control";
            runtimeInputs = with pkgs; [
              coreutils
              brightnessctl
              socat
            ];
            text = ''
                SOCKET_PATH="${config.ghaf.services.brightness.socketPath}"

                echo "Connecting to $SOCKET_PATH..."
                # Retry until socket exists
                while [ ! -S "$SOCKET_PATH" ]; do
                  echo "Waiting for QEMU socket to appear..."
                  sleep 1
                done

                # Connect and process messages
                socat -u UNIX-CONNECT:$SOCKET_PATH - | while read -r value; do
                if [[ "$value" =~ ^(\+5|5-)$ ]]; then
                  brightnessctl -d ${backlightDevice} set "$value"%
                fi
              done
            '';
          };
        in
        {
          enable = true;
          description = "Control display brightness using Nvidia driver";
          wantedBy = [ "multi-user.target" ];
          unitConfig.ConditionPathExists = "/sys/class/backlight/${backlightDevice}";
          serviceConfig = {
            Type = "simple";
            ExecStart = "${controlBrightnessScript}/bin/nvidia-brightness-control";
            Restart = "always";
            RestartSec = "1";
          };
        };
    }
    (mkIf (config.security.tpm2.enable && config.security.tpm2.tssGroup != null) {
      users.users.microvm.extraGroups = [
        config.security.tpm2.tssGroup
      ];
    })
    {
      # Set backlight brightness to max while host still has control over display
      services.udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="backlight", ATTR{brightness}="$attr{max_brightness}"
      '';
    }
  ]);
}
