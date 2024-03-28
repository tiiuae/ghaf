# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  configHost = config;
  vmName = "virtgpu-vm";
  # The socket is created in /tmp because it is accessible to both microvm and ghaf users
  gpuSocket = "/tmp/${vmName}-gpu.sock";
  run-sommelier = with pkgs;
    writeScriptBin "run-sommelier" ''
      #!${runtimeShell} -e
      exec ${sommelier}/bin/sommelier --virtgpu-channel -- $@
    '';
  run-wayland-proxy = with pkgs;
    writeScriptBin "run-wayland-proxy" ''
      #!${runtimeShell} -e
      exec ${wayland-proxy-virtwl}/bin/wayland-proxy-virtwl --virtio-gpu -- $@
    '';
  run-waypipe = with pkgs;
    writeScriptBin "run-waypipe" ''
      #!${runtimeShell} -e
      exec ${waypipe}/bin/waypipe --vsock -s 2:${toString config.ghaf.waypipe.port} server $@
    '';
  virtgpuvmBaseConfiguration = {
    imports = [
      (import ./common/vm-networking.nix {
        inherit vmName;
        macAddress = "02:00:00:03:05:01";
      })
      ({
        lib,
        pkgs,
        ...
      }: {
        ghaf = {
          users.accounts.enable = lib.mkDefault configHost.ghaf.users.accounts.enable;

          development = {
            ssh.daemon.enable = lib.mkDefault configHost.ghaf.development.ssh.daemon.enable;
            debug.tools.enable = lib.mkDefault configHost.ghaf.development.debug.tools.enable;
            nix-setup.enable = lib.mkDefault configHost.ghaf.development.nix-setup.enable;
          };
        };

        system.stateVersion = lib.trivial.release;

        nixpkgs.buildPlatform.system = configHost.nixpkgs.buildPlatform.system;
        nixpkgs.hostPlatform.system = configHost.nixpkgs.hostPlatform.system;

        environment.systemPackages = with pkgs; [
          sommelier
          wayland-proxy-virtwl
          waypipe
          run-sommelier
          run-wayland-proxy
          run-waypipe
          zathura
          chromium
          firefox
          wayland-utils
        ];

        # DRM fbdev emulation is disabled to get rid of the popup console window that appears when running a VM with virtio-gpu device
        boot.kernelParams = ["drm_kms_helper.fbdev_emulation=false"];

        hardware.opengl.enable = true;

        microvm = {
          optimize.enable = false;
          mem = 4096;
          vcpu = 4;
          hypervisor = "crosvm";
          shares = [
            {
              tag = "ro-store";
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
              proto = "virtiofs";
            }
          ];

          # GPU device is a separate service which is connected over vhost-user protocol
          crosvm.extraArgs = ["--vhost-user" "gpu,socket=${gpuSocket}"];

          # VSOCK is required for waypipe, 3 is the first available CID
          vsock.cid = 3;
        };

        imports = [../../../common];
      })
    ];
  };
  cfg = config.ghaf.virtualization.microvm.virtgpuvm;
in {
  options.ghaf.virtualization.microvm.virtgpuvm = {
    enable = lib.mkEnableOption "VirtgpuVM";

    extraModules = lib.mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        VirtgpuVM's NixOS configuration.
      '';
      default = [];
    };
  };

  config = lib.mkIf cfg.enable {
    microvm.vms."${vmName}" = {
      config = virtgpuvmBaseConfiguration // {imports = virtgpuvmBaseConfiguration.imports ++ cfg.extraModules;};
      specialArgs = {inherit lib;};
    };

    # This service creates a crosvm backend GPU device
    systemd.user.services."${vmName}-gpu" = let
      preStartScript = pkgs.writeShellScriptBin "prestart-crosvmgpu" ''
        if [[ -z "$WAYLAND_DISPLAY" ]]; then
          echo "WAYLAND_DISPLAY is not set"
          exit 1
        fi
        WAYLAND_SOCK=$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY
        if [[ ! -r "$WAYLAND_SOCK" ]]; then
          echo "Wayland socket $WAYLAND_SOCK is not readable"
          exit 1
        fi
      '';
      startScript = pkgs.writeShellScriptBin "start-crosvmgpu" ''
        rm -f ${gpuSocket}
        ${pkgs.crosvm}/bin/crosvm device gpu --socket ${gpuSocket} --wayland-sock $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY --params '{"context-types":"virgl:virgl2:cross-domain","egl":true,"vulkan":true}'
      '';
      postStartScript = pkgs.writeShellScriptBin "poststart-crosvmgpu" ''
        while ! [ -S ${gpuSocket} ]; do
              sleep .1
        done
        chgrp video ${gpuSocket}
        chmod 775 ${gpuSocket}
      '';
    in {
      enable = true;
      description = "crosvm gpu device";
      after = ["weston.service" "labwc.service"];
      serviceConfig = {
        Type = "simple";
        ExecStartPre = "${preStartScript}/bin/prestart-crosvmgpu";
        ExecStart = "${startScript}/bin/start-crosvmgpu";
        ExecStartPost = "${postStartScript}/bin/poststart-crosvmgpu";
        Restart = "always";
        RestartSec = "1";
      };
      startLimitIntervalSec = 0;
      wantedBy = ["ghaf-session.target"];
    };

    users.users."microvm".extraGroups = ["video"];

    ghaf.waypipe.enable = true;
  };
}
