# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  vmName = "gpu-vm";
  inherit (import ../../../lib/launcher.nix { inherit pkgs lib; }) rmDesktopEntries;

  ollama-jetson = pkgs.stdenv.mkDerivation rec {
    pname = "ollama-jetson";
    version = "0.5.11";

    src = pkgs.fetchurl {
      url = "https://github.com/ollama/ollama/releases/download/v${version}/ollama-linux-arm64.tgz";
      sha256 = "sha256-5NhY0q6gCPRfyaZvYkgNr7Mi/NtwfI/PM2Gg7irzfko=";
    };

    jetpackSrc = pkgs.fetchurl {
      url = "https://github.com/ollama/ollama/releases/download/v${version}/ollama-linux-arm64-jetpack6.tgz";
      sha256 = "sha256-f5UhEYEAn0cKgAv0jOC7JbplSDEygxGS/gun/AphTq0=";
    };

    nativeBuildInputs = with pkgs; [
      autoPatchelfHook
      makeWrapper
    ];

    buildInputs = with pkgs; [
      stdenv.cc.cc.lib
      nvidia-jetpack.l4t-cuda
      nvidia-jetpack.cudaPackages.cuda_cudart
      nvidia-jetpack.cudaPackages.cuda_cuobjdump
      nvidia-jetpack.cudaPackages.cuda_cupti
      nvidia-jetpack.cudaPackages.cuda_cuxxfilt
      nvidia-jetpack.cudaPackages.cuda_documentation
      nvidia-jetpack.cudaPackages.cuda_nvcc
      nvidia-jetpack.cudaPackages.cuda_nvdisasm
      nvidia-jetpack.cudaPackages.cuda_nvml_dev
      nvidia-jetpack.cudaPackages.cuda_nvprune
      nvidia-jetpack.cudaPackages.cuda_nvrtc
      nvidia-jetpack.cudaPackages.cuda_nvtx
      nvidia-jetpack.cudaPackages.cuda_sanitizer_api
      nvidia-jetpack.cudaPackages.cuda_profiler_api
      nvidia-jetpack.cudaPackages.libcublas
      nvidia-jetpack.cudaPackages.libcufft
      nvidia-jetpack.cudaPackages.libcurand
      nvidia-jetpack.cudaPackages.libnpp
    ];

    dontStrip = true;

    autoPatchelfIgnoreMissingDeps = [ "libcuda.so.1" ];

    sourceRoot = ".";

    unpackPhase = ''
      tar xzf $src
      tar xzf $jetpackSrc
    '';

    installPhase = ''
      # Create directories
      mkdir -p $out/bin
      mkdir -p $out/lib/ollama/cuda_jetpack6

      # Install main binary
      install -Dm755 bin/ollama $out/bin/ollama

      # Install base libraries
      cp -P lib/ollama/libggml-base.so $out/lib/ollama/
      cp -P lib/ollama/libggml-cpu-*.so $out/lib/ollama/

      # Install JetPack libraries
      cp -P lib/ollama/cuda_jetpack6/* $out/lib/ollama/cuda_jetpack6/

      # Wrap the binary with LD_LIBRARY_PATH
      wrapProgram $out/bin/ollama \
        --set LD_LIBRARY_PATH "${pkgs.nvidia-jetpack.l4t-cuda}/lib"
    '';

    meta = with lib; {
      description = "Ollama for Jetson devices";
      homepage = "https://github.com/ollama/ollama";
      license = licenses.mit;
      platforms = [ "aarch64-linux" ];
      maintainers = with maintainers; [ ];
    };
  };

  # Apply patches in nvidia-modules drivers to support display and GPU passthrough
  nvidia-modules = config.boot.kernelPackages.nvidia-modules.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or [ ]) ++ [
      # Patch for NVGPU driver
      ./gpuvm_res/0001-gpu-add-support-for-passthrough.patch
      # Patch for NVMAP, DRM, and MC modules to support passthrough
      ./gpuvm_res/0002-Add-support-for-gpu-display-passthrough.patch
      # Patch for nvdisplay driver
      ./gpuvm_res/0003-Add-support-for-display-passthrough.patch
    ];
  });

  # Derivation to build the GPU-VM guest device tree
  gpuvm-dtb = pkgs.stdenv.mkDerivation {
    name = "gpuvm-dtb";
    phases = [
      "unpackPhase"
      "buildPhase"
      "installPhase"
    ];
    src = ./gpuvm_res/tegra234-gpuvm.dts;
    nativeBuildInputs = with pkgs; [
      dtc
      binutils
    ];
    unpackPhase = ''
      cp $src ./tegra234-gpuvm.dts
    '';
    buildPhase = ''
      echo *********** config.hardware.deviceTree.kernelPackage ************
      ls -lah ${config.boot.kernelPackages.nvidia-modules.src}
      ls -lah ${config.boot.kernelPackages.nvidia-modules.src}/hardware/nvidia/t23x/nv-public/include/nvidia-oot/
      $CC -E -nostdinc \
        -I${config.boot.kernelPackages.nvidia-modules.src}/hardware/nvidia/t23x/nv-public/include/nvidia-oot \
        -I${config.boot.kernelPackages.nvidia-modules.src}/hardware/nvidia/t23x/nv-public/include/kernel \
        -undef -D__DTS__ \
        -x assembler-with-cpp \
        tegra234-gpuvm.dts > preprocessed.dts
      dtc -I dts -O dtb -o tegra234-gpuvm.dtb preprocessed.dts
    '';
    installPhase = ''
      mkdir -p $out
      cp tegra234-gpuvm.dtb $out/
    '';
  };

  gpuvmBaseConfiguration = {
    imports = [
      inputs.self.nixosModules.profiles
      inputs.impermanence.nixosModules.impermanence
      inputs.self.nixosModules.givc
      inputs.self.nixosModules.vm-modules
      (
        { lib, pkgs, ... }:
        let
          # A list of applications from all AppVMs
          enabledVms = lib.filterAttrs (_: vm: vm.enable) config.ghaf.virtualization.microvm.appvm.vms;
          virtualApps = lib.lists.concatMap (
            vm: map (app: app // { vmName = "${vm.name}-vm"; }) vm.applications
          ) config.ghaf.virtualization.microvm.appvm.vms;

          # Launchers for all virtualized applications that run in AppVMs
          virtualLaunchers = map (app: rec {
            inherit (app) name;
            inherit (app) description;
            #inherit (app) givcName;
            vm = app.vmName;
            # TODO: Has givc command been updated? Guivm has `start app..`, investigate..
            path = "${pkgs.givc-cli}/bin/givc-cli ${config.ghaf.givc.cliArgs} start app --vm ${vm} ${app.givcName}";
            inherit (app) icon;
          }) virtualApps;
          # Launchers for all desktop, non-virtualized applications that run in the GUIVM
          guivmLaunchers = map (app: {
            inherit (app) name;
            inherit (app) description;
            path = app.command;
            inherit (app) icon;
          }) cfg.applications;
        in
        {
          imports = [
            ../../common
            ../../desktop
            ../../reference/services
          ];

          ghaf = {
            # Profiles
            profiles = {
              debug.enable = lib.mkDefault config.ghaf.profiles.debug.enable;
              graphics.enable = true;
            };
            users.loginUser.enable = true;

            # Temporary solution
            users.admin.extraGroups = [
              "aduio"
              "video"
            ];

            development = {
              ssh.daemon.enable = lib.mkDefault config.ghaf.development.ssh.daemon.enable;
              debug.tools.enable = lib.mkDefault config.ghaf.development.debug.tools.enable;
              nix-setup.enable = lib.mkDefault config.ghaf.development.nix-setup.enable;
            };

            # System
            type = "system-vm";
            systemd = {
              enable = true;
              withName = "gpuvm-systemd";
              withAudit = config.ghaf.profiles.debug.enable;
              withHomed = true;
              withLocaled = true;
              withNss = true;
              withResolved = true;
              withTimesyncd = true;
              withDebug = config.ghaf.profiles.debug.enable;
              withHardenedConfigs = true;
            };

            # givc.guivm.enable = true;

            # Storage
            storagevm = {
              enable = true;
              name = vmName;
            };

            # Networking
            # ----------------
            # TODO: Temporarily disabled becasue of the following:
            # error: attribute 'gpu-vm' missing
            #  at /nix/store/hpc80jcslcl6glx2j081g88rymcxya0r-source/modules/microvm/common/vm-networking.nix:73:43:
            #      72|       links."10-${cfg.interfaceName}" = {
            #      73|         matchConfig.PermanentMACAddress = hosts.${cfg.vmName}.mac;
            #        |                                           ^
            #      74|         linkConfig.Name = cfg.interfaceName;
            # ----------------
            virtualization.microvm.vm-networking = {
              enable = true;
              inherit vmName;
            };

            # Services

            # Create launchers for regular apps running in the GUIVM and virtualized ones if GIVC is enabled
            graphics = {
              launchers = guivmLaunchers ++ lib.optionals config.ghaf.givc.enable virtualLaunchers;
              labwc = {
                autolock.enable = lib.mkDefault config.ghaf.graphics.labwc.autolock.enable;
                autologinUser = lib.mkDefault config.ghaf.graphics.labwc.autologinUser;
                securityContext = map (vm: {
                  identifier = vm.name;
                  color = vm.borderColor;
                }) (lib.attrsets.mapAttrsToList (name: vm: { inherit name; } // vm) enabledVms);
              };
            };

            # Logging
            logging.client.enable = config.ghaf.logging.enable;

            services = {
              disks = {
                enable = true;
                fileManager = "${pkgs.pcmanfm}/bin/pcmanfm";
              };
            };

            #reference.services.ollama = true;
            #xdgitems.enable = true;
          };

          services = {
            acpid = lib.mkIf config.ghaf.givc.enable {
              enable = true;
              lidEventCommands = ''
                case "$1" in
                  "button/lid LID close")
                    # Lock sessions
                    ${pkgs.systemd}/bin/loginctl lock-sessions

                    # Switch off display, if wayland is running
                    if ${pkgs.procps}/bin/pgrep -fl "wayland" > /dev/null; then
                      wl_running=1
                      WAYLAND_DISPLAY=/run/user/${builtins.toString config.ghaf.users.loginUser.uid}/wayland-0 ${pkgs.wlopm}/bin/wlopm --off '*'
                    else
                      wl_running=0
                    fi

                    # Initiate Suspension
                      ${pkgs.givc-cli}/bin/givc-cli ${config.ghaf.givc.cliArgs} suspend

                    # Enable display
                    if [ "$wl_running" -eq 1 ]; then
                      WAYLAND_DISPLAY=/run/user/${builtins.toString config.ghaf.users.loginUser.uid}/wayland-0 ${pkgs.wlopm}/bin/wlopm --on '*'
                    fi
                    ;;
                  "button/lid LID open")
                    # Command to run when the lid is opened
                    ;;
                esac
              '';
            };

            # Suspend inside Qemu causes segfault
            # See: https://gitlab.com/qemu-project/qemu/-/issues/2321
            logind.lidSwitch = "ignore";

            # We dont enable services.blueman because it adds blueman desktop entry
            dbus.packages = [ pkgs.blueman ];
          };

          systemd = {
            packages = [ pkgs.blueman ];

            services."waypipe-ssh-keygen" =
              let
                uid = "${toString config.ghaf.users.loginUser.uid}";
                pubDir = config.ghaf.security.sshKeys.waypipeSshPublicKeyDir;
                keygenScript = pkgs.writeShellScriptBin "waypipe-ssh-keygen" ''
                  set -xeuo pipefail
                  mkdir -p /run/waypipe-ssh
                  echo -en "\n\n\n" | ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f /run/waypipe-ssh/id_ed25519 -C ""
                  chown ${uid}:users /run/waypipe-ssh/*
                  cp /run/waypipe-ssh/id_ed25519.pub ${pubDir}/id_ed25519.pub
                  chown -R ${uid}:users ${pubDir}
                '';
              in
              {
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

          environment = {
            systemPackages =
              (rmDesktopEntries [
                #pkgs.waypipe
                pkgs.networkmanagerapplet
                pkgs.gnome-calculator
                pkgs.sticky-notes
              ])
              ++ [
                pkgs.bt-launcher
                pkgs.pamixer
                pkgs.eww
                pkgs.wlr-randr
                ollama-jetson
                pkgs.nvidia-jetpack.l4t-tools
                pkgs.nvidia-jetpack.l4t-cuda
                pkgs.nvidia-jetpack.l4t-firmware
                pkgs.nvidia-jetpack.l4t-wayland
              ]
              #++ [ pkgs.ctrl-panel ]
              ++ (lib.optional (
                config.ghaf.profiles.debug.enable && config.ghaf.virtualization.microvm.idsvm.mitmproxy.enable
              ) pkgs.mitmweb-ui)
              # Packages for checking hardware acceleration
              ++ lib.optionals config.ghaf.profiles.debug.enable [
                pkgs.glxinfo
                pkgs.libva-utils
                pkgs.glib
              ];
          };

          time.timeZone = config.time.timeZone;
          system.stateVersion = lib.trivial.release;

          nixpkgs = {
            buildPlatform.system = config.nixpkgs.buildPlatform.system;
            hostPlatform.system = config.nixpkgs.hostPlatform.system;
          };

          microvm = {
            # Optimize is disabled because when it is enabled, qemu is built without libusb
            optimize.enable = false;
            # tegra234-gpuvm.tds is gennerated with 4 cpu cores. Update DTS if you change this value.
            vcpu = 4;
            mem = 6000;
            hypervisor = "qemu";

            # We add these kernel parameters, in order that the BPMP in the VM turn off
            # the clocks that are not used, and the power domain that are not used in the VM
            # but are used in the host.
            kernelParams = [ "clk_ignore_unused pd_ignore_unused" ];

            shares = [
              # {
              #   tag = "waypipe-ssh-public-key";
              #   source = config.ghaf.security.sshKeys.waypipeSshPublicKeyDir;
              #   mountPoint = config.ghaf.security.sshKeys.waypipeSshPublicKeyDir;
              #   proto = "virtiofs";
              # }
              {
                tag = "ro-store";
                source = "/nix/store";
                mountPoint = "/nix/.ro-store";
                proto = "virtiofs";
              }
            ];
            writableStoreOverlay = lib.mkIf config.ghaf.development.debug.tools.enable "/nix/.rw-store";

            qemu = {

              # Devices to passthrough to the GPU-VM
              extraArgs = [
                "-dtb"
                "${gpuvm-dtb.out}/tegra234-gpuvm.dtb"
                "-device"
                "vfio-platform,host=60000000.vm_hs_p,mmio-base=0x60000000"
                "-device"
                "vfio-platform,host=80000000.vm_cma_p,mmio-base=0x80000000"
                "-device"
                "vfio-platform,host=100000000.vm_cma_vram_p,mmio-base=0x100000000"
                "-device"
                "vfio-platform,host=17000000.gpu"
                "-device"
                "vfio-platform,host=13e00000.host1x_pt"
                "-device"
                "vfio-platform,host=15340000.vic"
                "-device"
                "vfio-platform,host=15480000.nvdec"
                "-device"
                "vfio-platform,host=15540000.nvjpg"
                "-device"
                "vfio-platform,host=d800000.dce"
                "-device"
                "vfio-platform,host=13800000.display"
              ];

              machine =
                {
                  # Use the same machine type as the host
                  x86_64-linux = "q35";
                  aarch64-linux = "virt";
                }
                .${config.nixpkgs.hostPlatform.system};
            };
          };
        }
      )
    ];
  };
  cfg = config.ghaf.virtualization.microvm.gpuvm;
in
{
  options.ghaf.virtualization.microvm.gpuvm = {
    enable = lib.mkEnableOption "GPUVM";

    extraModules = lib.mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        gpuvm's NixOS configuration.
      '';
      default = [ ];
    };

    # GUIVM uses a VSOCK which requires a CID
    # There are several special addresses:
    # VMADDR_CID_HYPERVISOR (0) is reserved for services built into the hypervisor
    # VMADDR_CID_LOCAL (1) is the well-known address for local communication (loopback)
    # VMADDR_CID_HOST (2) is the well-known address of the host
    # CID 3 is the lowest available number for guest virtual machines
    vsockCID = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = ''
        Context Identifier (CID) of the GUIVM VSOCK
      '';
    };

    applications = lib.mkOption {
      description = ''
        Applications to include in the GUIVM
      '';
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
    services.udev.extraRules = ''
      # Allow group kvm to all devices that are binded to vfio
      SUBSYSTEM=="vfio",GROUP="kvm"
      SUBSYSTEM=="chardrv", KERNEL=="bpmp-host", GROUP="kvm", MODE="0660"
    '';

    # Make sure that GPU-VM runs after the binding services are enabled
    systemd.services."microvm@gpu-vm".after = [ "bindGpu.service" ];

    # Service to bind the devices to passthourgh to the VFIO driver
    systemd.services.bindGpu = {
      description = "Bind GPU devices to the vfio-platform driver";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = "yes";
        ExecStartPre = [
          ''${pkgs.bash}/bin/bash -c "echo vfio-platform > /sys/bus/platform/devices/80000000.vm_cma_p/driver_override"''
          ''${pkgs.bash}/bin/bash -c "echo vfio-platform > /sys/bus/platform/devices/17000000.gpu/driver_override"''
          ''${pkgs.bash}/bin/bash -c "echo vfio-platform > /sys/bus/platform/devices/13e00000.host1x_pt/driver_override"''
          ''${pkgs.bash}/bin/bash -c "echo vfio-platform > /sys/bus/platform/devices/15340000.vic/driver_override"''
          ''${pkgs.bash}/bin/bash -c "echo vfio-platform > /sys/bus/platform/devices/15480000.nvdec/driver_override"''
          ''${pkgs.bash}/bin/bash -c "echo vfio-platform > /sys/bus/platform/devices/15540000.nvjpg/driver_override"''
          ''${pkgs.bash}/bin/bash -c "echo vfio-platform > /sys/bus/platform/devices/d800000.dce/driver_override"''
          ''${pkgs.bash}/bin/bash -c "echo vfio-platform > /sys/bus/platform/devices/13800000.display/driver_override"''
          ''${pkgs.bash}/bin/bash -c "echo vfio-platform > /sys/bus/platform/devices/100000000.vm_cma_vram_p/driver_override"''
          ''${pkgs.bash}/bin/bash -c "echo vfio-platform > /sys/bus/platform/devices/60000000.vm_hs_p/driver_override"''
        ];
        ExecStart = [
          ''${pkgs.bash}/bin/bash -c "echo 80000000.vm_cma_p > /sys/bus/platform/drivers/vfio-platform/bind"''
          ''${pkgs.bash}/bin/bash -c "echo 17000000.gpu > /sys/bus/platform/drivers/vfio-platform/bind"''
          ''${pkgs.bash}/bin/bash -c "echo 13e00000.host1x_pt > /sys/bus/platform/drivers/vfio-platform/bind"''
          ''${pkgs.bash}/bin/bash -c "echo 15340000.vic > /sys/bus/platform/drivers/vfio-platform/bind"''
          ''${pkgs.bash}/bin/bash -c "echo 15480000.nvdec > /sys/bus/platform/drivers/vfio-platform/bind"''
          ''${pkgs.bash}/bin/bash -c "echo 15540000.nvjpg > /sys/bus/platform/drivers/vfio-platform/bind"''
          ''${pkgs.bash}/bin/bash -c "echo d800000.dce > /sys/bus/platform/drivers/vfio-platform/bind"''
          ''${pkgs.bash}/bin/bash -c "echo 13800000.display > /sys/bus/platform/drivers/vfio-platform/bind"''
          ''${pkgs.bash}/bin/bash -c "echo 100000000.vm_cma_vram_p > /sys/bus/platform/drivers/vfio-platform/bind"''
          ''${pkgs.bash}/bin/bash -c "echo 60000000.vm_hs_p > /sys/bus/platform/drivers/vfio-platform/bind"''
        ];
      };
    };

    # Apply the device tree overlay to host DTB to support GPU passthrough
    hardware.deviceTree.overlays = [
      {
        name = "GPU/Display passthrough overlay to host DTB";
        dtsFile = ./gpuvm_res/gpu_passthrough_overlay.dts;
      }
    ];

    microvm.vms."${vmName}" = {
      autostart = true;
      inherit (inputs) nixpkgs;
      config = gpuvmBaseConfiguration // {
        hardware.nvidia = {
          modesetting.enable = true;
          open = false; # Important for Tegra
        };

        # Create admin home folder; temporary solution
        users.users.ghaf.createHome = lib.mkForce true;
        users.users.ghaf.home = lib.mkForce "/home/ghaf";

        hardware.firmwareCompression = lib.mkForce "none";
        hardware.firmware = with pkgs.nvidia-jetpack; [
          l4t-firmware
          l4t-xusb-firmware # usb firmware also present in linux-firmware package, but that package is huge and has much more than needed
          cudaPackages.vpi2-firmware # Optional, but needed for pva_auth_allowlist firmware file used by VPI2
        ];

        #####################################################################
        # Nvidia graphics for wayland are commeted becuase it is not working
        # and when enable the GPU applications do not work
        #####################################################################

        # # Used by libEGL_nvidia.so.0
        # environment.etc."egl/egl_external_platform.d".source =
        #   "${pkgs.addDriverRunpath.driverLink}/share/egl/egl_external_platform.d/";

        # # If we aren't using modesetting, we won't have a DRM device with the
        # # "master-of-seat" tag, so "loginctl show-seat seat0" reports
        # # "CanGraphical=false" and consequently lightdm doesn't start. We override
        # # that here.
        # services.xserver.displayManager.lightdm.extraConfig =
        #   lib.optionalString (!config.hardware.nvidia.modesetting.enable)
        #     ''
        #       logind-check-graphical = false
        #     '';

        # # Force the driver, since otherwise the fbdev or modesetting X11 drivers
        # # may be used, which don't work and can interfere with the correct
        # # selection of GLX drivers.
        # services.xserver.drivers = lib.mkForce (
        #   lib.singleton {
        #     name = "nvidia";
        #     modules = [ pkgs.nvidia-jetpack.l4t-3d-core ];
        #     display = true;
        #     screenSection = ''
        #       Option "AllowEmptyInitialConfiguration" "true"
        #     '';
        #   }
        # );

        # hardware.graphics.package = pkgs.nvidia-jetpack.l4t-3d-core;

        # hardware.graphics.extraPackages =
        #   with pkgs.nvidia-jetpack;
        #   # l4t-core provides - among others - libnvrm_gpu.so and libnvrm_mem.so.
        #   # The l4t-core/lib directory is directly set in the DT_RUNPATH of
        #   # l4t-cuda's libcuda.so, thus the standard driver doesn't need them to be
        #   # added in ${driverLink}.
        #   #
        #   # However, this isn't the case for cuda_compat's driver currently, which
        #   # is why we're including this derivation in extraPackages.
        #   #
        #   # To avoid exposing a bunch of other unrelated libraries from l4t-core,
        #   # we're wrapping l4t-core in a derivation that only exposes the two
        #   # required libraries.
        #   #
        #   # Those libraries should ideally be directly accessible from the
        #   # DT_RUNPATH of cuda_compat's libcuda.so in the same way, but this
        #   # requires more integration between upstream Nixpkgs and jetpack-nixos.
        #   # When that happens, please remove l4tCoreWrapper below.
        #   let
        #     l4tCoreWrapper = pkgs.stdenv.mkDerivation {
        #       name = "l4t-core-wrapper";
        #       phases = [ "installPhase" ];
        #       installPhase = ''
        #         runHook preInstall

        #         mkdir -p $out/lib
        #         ln -s ${l4t-core}/lib/libnvrm_gpu.so $out/lib/libnvrm_gpu.so
        #         ln -s ${l4t-core}/lib/libnvrm_mem.so $out/lib/libnvrm_mem.so

        #         runHook postInstall
        #       '';
        #     };
        #   in
        #   [
        #     l4tCoreWrapper
        #     l4t-cuda
        #     l4t-nvsci # cuda may use nvsci
        #     l4t-gbm
        #     l4t-wayland
        #   ];

        imports = gpuvmBaseConfiguration.imports ++ cfg.extraModules;
        boot = {
          inherit (config.boot) kernelPackages;
          extraModulePackages = [ nvidia-modules ];

          #####################################################################
          # Nvidia modules for wayland are commeted becuase it is not working
          # and when enable the GPU applications do not work
          #####################################################################

          # kernelModules = [
          #   "tegra_drm"
          #   "nvidia"
          #   "nvidia-modeset"
          #   "nvidia-drm"
          # ];

          # extraModprobeConfig = ''
          #   nvidia-modeset
          #   nvidia-drm
          #   options nvidia-drm modeset=1
          # '';

          kernelPatches = [
            {
              name = "Virtio FS to support microvm";
              patch = null;
              extraStructuredConfig = with lib.kernel; {
                VIRTIO_FS = module;
              };
            }
            {
              name = "Bpmp virtualization guest kernel configuration";
              patch = null;
              extraStructuredConfig = with lib.kernel; {
                TEGRA_BPMP_GUEST_PROXY = yes;
              };
            }
            {
              name = "Fixed chipid hardcoded for tegra-apbmisc";
              patch = ./gpuvm_res/0001-tegra-fixed-chip-id.patch;
            }
          ];

          # Modules to support microvm storage system
          initrd = {
            # Override the available kernel modules
            availableKernelModules = lib.mkForce [
              "virtio_mmio"
              "virtio_pci"
              "virtio_blk"
              "9pnet_virtio"
              "9p"
              "virtiofs"
              "overlay"
              "dm_mod"
              "ext4"
            ];
            # Override the required kernel modules
            kernelModules = lib.mkForce [
              "virtio_mmio"
              "virtio_pci"
              "virtio_blk"
              "9pnet_virtio"
              "9p"
              "virtiofs"
              "overlay"
              "dm_mod"
              "ext4"
            ];
          };
        };
      };
    };
  };
}
