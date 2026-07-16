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

  # Same shim kmscube uses (gpu-vm/sources): forces every gbm_surface_create*
  # to a plain no-modifier surface. On this L4T guest the NVIDIA EGL exposes
  # only the GBM/Wayland/X11/Surfaceless platforms (no EGL device platform), and
  # the modifier GBM path EGL_BAD_ALLOCs. cosmic-comp (smithay udev backend)
  # must go through GBM, so it needs this preloaded to create scanout surfaces.
  gbm-nomod-shim = pkgs.runCommandCC "gbm-nomod-shim" { } ''
    mkdir -p $out/lib
    $CC -O2 -fPIC -shared -o $out/lib/gbm-nomod-shim.so \
      ${./sources/gbm-nomod-shim.c} -ldl
  '';
  # cosmic-comp needs the no-modifier GBM path (modifier surfaces BAD_ALLOC on
  # this L4T EGL); EGL device-enumeration is handled compositor-side by the
  # cosmic-comp-egl-device-optional patch (overlay above), not a preload.
  cosmicPreload = "${gbm-nomod-shim}/lib/gbm-nomod-shim.so";
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
        # Pin cosmic-comp to the GA10B render node. This cosmic-comp (1.1.0)
        # PREPENDS /dev/dri/ to COSMIC_RENDER_DEVICE, so it needs the BARE node name
        # ("renderD128"), not an absolute path -- an absolute value doubles to
        # /dev/dri//dev/dri/renderD128 -> "not found" -> software renderer -> no
        # output. But `ghaf.graphics.cosmic.renderDevice` is typed as an absolute
        # path (and cosmic/default.nix assigns it verbatim to COSMIC_RENDER_DEVICE),
        # so it can't carry a bare name. Set the option null (module skips the env)
        # and export the bare name directly. renderD128 = card0/nvgpu's render node
        # (card1, the host1x tegra-drm, is dropped from seat0 below).
        renderDevice = lib.mkForce null;
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
        virtualization.host.bpmp.enable = false;
        passthroughs.host.uarta.enable = false;
        # TODO: uarti passthrough is currently broken, it will be enabled
        # later after a further analysis.
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

    # libEGL_nvidia.so.0 discovers its EGL platform modules here.
    environment.etc."egl/egl_external_platform.d".source =
      "${pkgs.addDriverRunpath.driverLink}/share/egl/egl_external_platform.d/";

    environment.sessionVariables = {
      COSMIC_RENDER_DEVICE = "renderD128";
      COSMIC_POLL_DMABUF_FENCES = "1";
      LIBSEAT_BACKEND = "seatd";
      LD_PRELOAD = cosmicPreload;
      GBM_BACKEND = "nvidia-drm";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      __EGL_VENDOR_LIBRARY_FILENAMES = "/run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json";
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

    services.seatd.enable = true;

    systemd.services.seatd.environment.SEATD_VTBOUND = "0";
    systemd.services.greetd = {
      environment = {
        COSMIC_RENDER_DEVICE = "renderD128";
        COSMIC_POLL_DMABUF_FENCES = "1";
        LD_PRELOAD = cosmicPreload;
      };
      serviceConfig = { 
        ExecStartPre = [
          "${pkgs.kbd}/bin/kbd_mode -f -d -C /dev/tty1"
        ];
        ExecStopPost = [
          "${pkgs.kbd}/bin/kbd_mode -f -u -C /dev/tty1"
        ];
      };
    };

    # Cosmic on orin
    hardware.graphics = {
      package = lib.mkForce (pkgs.symlinkJoin {
        name = "l4t-3d-core-egl-gbm-1.1.3";
        paths = [
          # single-device fallback: on Tegra the EGL device's DRM node
          # (tegra-drm) never path-matches the gbm fd (nvidia-drm), so
          # stock matching always fails eglInitialize on GBM.
          (pkgs.egl-gbm.overrideAttrs (o: {
            patches = (o.patches or [ ]) ++ [
              ./patches/egl-gbm-single-device-fallback.patch
            ];
          }))
          pkgs.nvidia-jetpack.l4t-3d-core
        ];
        postBuild = ''
          rm -f $out/share/egl/egl_external_platform.d/nvidia_gbm.json
        '';
      });
      extraPackages = lib.mkForce( 
        (with pkgs.nvidia-jetpack; [
          l4t-core
          l4t-cuda
          l4t-nvsci
          l4t-wayland
        ])
        ++ [
          # l4t-gbm minus its bundled libnvidia-egl-gbm 1.1.0 (and its
          # platform json): the nixpkgs egl-gbm 1.1.3 in `package`
          # provides that library; keep only the nvidia-drm_gbm backend.
          (pkgs.symlinkJoin {
            name = "l4t-gbm-sans-egl-gbm";
            paths = [ pkgs.nvidia-jetpack.l4t-gbm ];
            postBuild = ''
              rm -f $out/lib/libnvidia-egl-gbm.so*
              rm -f $out/lib64/libnvidia-egl-gbm.so*
              rm -f $out/share/egl/egl_external_platform.d/nvidia_gbm.json
            '';
          })
        ]);
    };

    #security.pam.services.greetd.rules.auth.unix.settings.use_first_pass = lib.mkForce false;
    #security.pam.services.cosmic-greeter.rules.auth.unix.settings.use_first_pass = lib.mkForce false;
    #ghaf.services.user-provisioning.enable = lib.mkForce false;
    services.udev.extraRules = ''
      KERNEL=="nvmap", GROUP="video", MODE="0660"
      KERNEL=="nvhost-*", GROUP="video", MODE="0660"
      KERNEL=="nvgpu*", GROUP="video", MODE="0660"
      ENV{DEVNAME}=="/dev/nvgpu/*", GROUP="video", MODE="0660"
      SUBSYSTEM=="drm", DEVPATH=="*/66010000.host1x/*", ENV{ID_SEAT}="seat-unused"
      SUBSYSTEM=="input", ENV{ID_INPUT}=="1", TAG+="uaccess"
    '';

    # Cosmic on orin
    users.users.cosmic-greeter.extraGroups = [ "seat" ];
    users.users.ghaf.extraGroups = [
      "seat"
      "video"
      # The GIVC TLS material under /run/givc (a storagevm mount) is root:users
      # 0750; the App VM launchers shell out to givc-cli as the graphical ghaf
      # user, which has a private primary group. Without "users" the client
      # cannot read the cert/key and every App VM launch fails "Permission
      # denied (os error 13)" -- no window ever appears.
      "users"
    ];
  };
}