# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# NVIDIA Jetson Orin Profile
#
# This profile configures Ghaf for NVIDIA Jetson Orin hardware (AGX, NX).
#
# VM Configuration on Jetson:
# ===========================
# Enabled VMs:
# - Net VM (netvmBase exported for composition)
# - Admin VM (adminvmBase exported for composition)
#
# Disabled VMs (architectural reasons):
# - GUI VM: GPU passthrough not supported, desktop runs natively on host (COSMIC)
# - Audio VM: Audio hardware directly accessible from host
# - IDS VM: Resource constraints on embedded platform
# - App VMs: No GUI VM means no Waypipe, apps run on host or via Docker
#
# Both netvmBase and adminvmBase are exported for composition needs.
#
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.ghaf.profiles.orin;
  hostGlobalConfig = config.ghaf.global-config;
  ensureSystemProfile = pkgs.writeShellApplication {
    name = "ghaf-ensure-system-profile";
    runtimeInputs = with pkgs; [
      coreutils
      nix
    ];
    text = ''
      profile=/nix/var/nix/profiles/system
      registration=/nix-path-registration
      current_system=$(readlink -f /run/current-system)
      generation_link=/nix/var/nix/profiles/system-1-link

      if [ -z "$current_system" ] || [ ! -e "$current_system" ]; then
        echo "Current system closure is unavailable" >&2
        exit 1
      fi

      if [ ! -f "$registration" ] && [ -L "$profile" ] && [ "$(readlink -f "$profile")" = "$current_system" ]; then
        exit 0
      fi

      if [ -f "$registration" ]; then
        nix-store --load-db < "$registration"
        rm -f "$registration"
        touch /etc/NIXOS
      fi

      mkdir -p /nix/var/nix/profiles
      ln -sfn "$current_system" "$generation_link"
      ln -sfn system-1-link "$profile"
    '';
  };
in
{
  _file = ./orin.nix;

  options.ghaf.profiles.orin = {
    enable = lib.mkEnableOption "the basic Nvidia Orin config";

    # Net VM base configuration for profiles to extend
    netvmBase = lib.mkOption {
      type = lib.types.unspecified;
      readOnly = true;
      description = ''
        Orin Net VM base configuration.
        Profiles can extend this with extendModules if customization needed.
      '';
    };

    # Admin VM base configuration for profiles to extend
    adminvmBase = lib.mkOption {
      type = lib.types.unspecified;
      readOnly = true;
      description = ''
        Orin Admin VM base configuration.
        Profiles can extend this with extendModules if customization needed.
      '';
    };

    # GPU VM base configuration for profiles to extend
    gpuvmBase = lib.mkOption {
      type = lib.types.unspecified;
      readOnly = true;
      description = ''
        Orin GPU VM base configuration.
        Profiles can extend this with extendModules if customization needed.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    ghaf = {
      # Orin devices are embedded, not laptops
      hardware.definition.type = "embedded";

      profiles = {
        # Export Net VM base for profiles to extend
        orin.netvmBase = lib.nixosSystem {
          modules = [
            inputs.microvm.nixosModules.microvm
            inputs.self.nixosModules.netvm-base
            # Import nixpkgs config module to get overlays
            {
              nixpkgs = {
                hostPlatform.system = "aarch64-linux";
                inherit (config.nixpkgs) overlays;
                inherit (config.nixpkgs) config;
              };
            }
          ];
          specialArgs = lib.ghaf.vm.mkSpecialArgs {
            inherit lib inputs;
            globalConfig = hostGlobalConfig;
            hostConfig = lib.ghaf.vm.mkHostConfig {
              inherit config;
              vmName = "net-vm";
            };
            # Note: netvm.wifi now controlled via globalConfig.features.wifi
          };
        };

        # Export Admin VM base for profiles to extend
        orin.adminvmBase = lib.nixosSystem {
          modules = [
            inputs.microvm.nixosModules.microvm
            inputs.self.nixosModules.adminvm-base
            # Import nixpkgs config module to get overlays
            {
              nixpkgs = {
                hostPlatform.system = "aarch64-linux";
                inherit (config.nixpkgs) overlays;
                inherit (config.nixpkgs) config;
              };
            }
          ];
          specialArgs = lib.ghaf.vm.mkSpecialArgs {
            inherit lib inputs;
            globalConfig = hostGlobalConfig;
            hostConfig = lib.ghaf.vm.mkHostConfig {
              inherit config;
              vmName = "admin-vm";
            };
          };
        };

        # Export GPU VM base for profiles to extend
        orin.gpuvmBase = lib.nixosSystem {
          modules = [
            inputs.microvm.nixosModules.microvm
            inputs.self.nixosModules.gpuvm-base
            # Import nixpkgs config module to get overlays
            {
              nixpkgs = {
                hostPlatform.system = "aarch64-linux";
                inherit (config.nixpkgs) overlays;
                inherit (config.nixpkgs) config;
              };
            }
          ];
          specialArgs = lib.ghaf.vm.mkSpecialArgs {
            inherit lib inputs;
            globalConfig = hostGlobalConfig;
            hostConfig = lib.ghaf.vm.mkHostConfig {
              inherit config;
              vmName = "gpu-vm";
            };
          };
        };

        graphics = {
          enable = true;
          # Explicitly enable auto-login for Orins
          autoLogin = {
            enable = true;
            user = config.ghaf.users.admin.name;
          };
          # We might be able to enable bluetooth and networkManager
          # together with applets without dbusProxy on Orins
          bluetooth.applet.enable = false;
          networkManager.applet.enable = false;
        };
      };

      # Disable suspend by default, not working as intended
      services.power-manager.suspend.enable = false;

      graphics.cosmic = {
        # Crucial for Orin devices to use the correct render device
        # Also needs 'mesa' to be in hardware.graphics.extraPackages
        renderDevice = lib.mkDefault "/dev/dri/renderD128";
        # Keep only essential applets for Orin devices
        topPanelApplets.right = [
          "com.system76.CosmicAppletInputSources"
          "com.system76.CosmicAppletStatusArea"
          "com.system76.CosmicAppletTiling"
          "com.system76.CosmicAppletPower"
        ];
        bottomPanelApplets.right = [
          "com.system76.CosmicAppletInputSources"
          "com.system76.CosmicAppletStatusArea"
          "com.system76.CosmicAppletTiling"
          "com.system76.CosmicAppletPower"
        ];
        screenRecorder.enable = false;
        idleManagement.screenOffTime = lib.mkForce 0;
        idleManagement.suspendOnBattery = lib.mkForce 0;
        idleManagement.suspendOnAC = lib.mkForce 0;
      };

      reference.programs.windows-launcher.enable = true;
      reference.host-demo-apps.demo-apps.enableDemoApplications = true;

      hardware.nvidia = {
        virtualization.enable = true;
        # MGBE0 passthrough is AGX-only, so it's enabled per-SoM in the AGX
        # modules, not in this NX-shared profile: NX has no MGBE0 and would
        # crash net-vm on `-device vfio-platform,host=6800000.ethernet`.
        passthroughs.host.uarta.enable = false;
        # uarti passthrough exits(1) in QEMU's add_fdt_node() (dynamic sysbus
        # device, no FDT binding); needs a binding like mgbe0_net_vm has.
        passthroughs.uarti_net_vm.enable = false;
      };

      # Virtualization options
      virtualization = {
        microvm-host = {
          enable = true;
          networkSupport = true;
          sharedVmDirectory = {
            enable = false;
          };
        };

        microvm = {
          netvm = {
            enable = true;
            # wifi is now controlled via ghaf.global-config.features.wifi
            # Use evaluatedConfig pattern - extend netvmBase with vmConfig modules
            evaluatedConfig = config.ghaf.profiles.orin.netvmBase.extendModules {
              modules = lib.ghaf.vm.applyVmConfig {
                inherit config;
                vmName = "netvm";
              };
            };
          };

          adminvm = {
            enable = true;
            # Use evaluatedConfig pattern - common is passed via hostConfig
            evaluatedConfig = cfg.adminvmBase;
          };

          # GPU VM: enable comes from the gpu-vm passthrough module
          # (ghaf.hardware.nvidia.passthroughs.gpu_vm), which sets
          # ghaf.virtualization.microvm.gpuvm.enable = true under its own mkIf.
          # Here we only provide the evaluatedConfig, extending gpuvmBase with
          # the hardware.definition.gpuvm.extraModules (DTB, vfio, guest kernel)
          # via applyVmConfig.
          gpuvm = {
            evaluatedConfig = config.ghaf.profiles.orin.gpuvmBase.extendModules {
              modules = lib.ghaf.vm.applyVmConfig {
                inherit config;
                vmName = "gpuvm";
              };
            };
          };

          idsvm = {
            enable = false;
          };

          guivm = {
            enable = false;
            # fprint/yubikey/brightness now controlled via ghaf.global-config.features
          };

          audiovm = {
            enable = false;
            # audio now controlled via ghaf.global-config.features.audio
          };
        };

        #nvidia-podman.daemon.enable = true;
        nvidia-docker.daemon.enable = true;
      };

      host.networking = {
        enable = true;
      };

      # Allow admin UI login
      users.admin.enableUILogin = true;
    };
    environment.variables.SYSTEMD_RELAX_ESP_CHECKS = "1";

    system.build.installBootLoader = lib.mkForce (
      pkgs.writeShellScript "install-bootloader-wrapper" ''
        echo "[ghaf] running systemd-boot (non-fatal)"

        export SYSTEMD_RELAX_ESP_CHECKS=1

        ${pkgs.systemd}/bin/bootctl --esp-path=/boot install || true
        ${pkgs.systemd}/bin/bootctl --esp-path=/boot update || true

        exit 0
      ''
    );

    # Cosmic on orin
    environment.sessionVariables = {
      GBM_BACKEND = "dri";
      __EGL_VENDOR_LIBRARY_FILENAMES = "/run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json";
    };

    systemd.services.ghaf-ensure-system-profile = {
      description = "Ensure persistent NixOS system profile exists";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      before = [ "nix-gc.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${ensureSystemProfile}/bin/ghaf-ensure-system-profile";
      };
    };

    # Cosmic on orin
    hardware.graphics.extraPackages = lib.mkAfter [
      pkgs.mesa
    ];

    # Cosmic on orin
    users.users.ghaf.extraGroups = [ "video" ];

  };
}
