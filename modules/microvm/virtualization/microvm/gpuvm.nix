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
  macAddress = "02:00:00:04:04:04";
  isGuiVmEnabled = config.ghaf.virtualization.microvm.guivm.enable;
  sshKeysHelper = pkgs.callPackage ../../../../packages/ssh-keys-helper {
    inherit pkgs;
    inherit config;
  };
 
  # Apply patches in nvidia-oot drivers to support display and GPU passthrough
  nvidia-oot = config.boot.kernelPackages.nvidia-oot.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or []) ++ [
      # Patch for NVGPU driver
      ./0001-gpu-add-support-for-passthrough.patch
      # Patch for NVMAP, DRM, and MC modules to support passthrough
      ./0002-Add-support-for-gpu-display-passthrough.patch
      # Patch for nvdisplay driver
      ./0003-Add-support-for-display-passthrough.patch
    ];
  });
 
  # Derivation to build the GPU-VM guest device tree
  gpuvm-dtb = pkgs.stdenv.mkDerivation {
    name = "gpuvm-dtb";
    phases = [ "unpackPhase" "buildPhase" "installPhase" ];
    src = ./tegra234-gpuvm.dts;
    nativeBuildInputs = with pkgs; [
      dtc
    ];
    unpackPhase = ''
      cp $src ./tegra234-gpuvm.dts
    '';
    buildPhase = ''
      echo *********** config.hardware.deviceTree.kernelPackage ************
      ls -lah ${config.boot.kernelPackages.nvidia-oot.src}
      ls -lah ${config.boot.kernelPackages.nvidia-oot.src}/hardware/nvidia/t23x/nv-public/include/nvidia-oot/
      $CC -E -nostdinc \
        -I${config.boot.kernelPackages.nvidia-oot.src}/hardware/nvidia/t23x/nv-public/include/nvidia-oot \
        -I${config.boot.kernelPackages.nvidia-oot.src}/hardware/nvidia/t23x/nv-public/include/kernel \
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
      inputs.impermanence.nixosModules.impermanence
      inputs.self.nixosModules.givc-guivm
      (import ./common/vm-networking.nix {
        inherit
          config
          lib
          vmName
          macAddress
          ;
        internalIP = 6;
      })

      ./common/storagevm.nix

      # To push logs to central location
      ../../../common/logging/client.nix
      (
        { lib, ... }:
        {
          imports = [ ../../../common ];

          ghaf = {
            users.accounts.enable = lib.mkDefault config.ghaf.users.accounts.enable;
            profiles.debug.enable = lib.mkDefault config.ghaf.profiles.debug.enable;
            development = {
              # NOTE: SSH port also becomes accessible on the network interface
              #       that has been passed through to gpuvm
              ssh.daemon.enable = lib.mkDefault config.ghaf.development.ssh.daemon.enable;
              debug.tools.enable = lib.mkDefault config.ghaf.development.debug.tools.enable;
              nix-setup.enable = lib.mkDefault config.ghaf.development.nix-setup.enable;
            };
            systemd = {
              enable = true;
              withName = "gpuvm-systemd";
              withAudit = config.ghaf.profiles.debug.enable;
              withPolkit = true;
              withResolved = true;
              withTimesyncd = true;
              withDebug = config.ghaf.profiles.debug.enable;
              withHardenedConfigs = true;
            };
            #givc.gpuvm.enable = true;
            # Logging client configuration
            logging.client.enable = config.ghaf.logging.client.enable;
            logging.client.endpoint = config.ghaf.logging.client.endpoint;
            # storagevm = {
            #   enable = true;
            #   name = "gpuvm";
            #   directories = [ "/etc/NetworkManager/system-connections/" ];
            # };
          };

          time.timeZone = config.time.timeZone;
          system.stateVersion = lib.trivial.release;

          nixpkgs = {
            buildPlatform.system = config.nixpkgs.buildPlatform.system;
            hostPlatform.system = config.nixpkgs.hostPlatform.system;
          };

          networking = {
            firewall.allowedTCPPorts = [ 53 ];
            firewall.allowedUDPPorts = [ 53 ];
          };

          services.openssh = config.ghaf.security.sshKeys.sshAuthorizedKeysCommand;

          # WORKAROUND: Create a rule to temporary hardcode device name for Wi-Fi adapter on x86
          # TODO this is a dirty hack to guard against adding this to Nvidia/vm targets which
          # dont have that definition structure yet defined. FIXME.
          # TODO the hardware.definition should not even be exposed in targets that do not consume it
          # services.udev.extraRules = lib.mkIf (config.ghaf.hardware.definition.network.pciDevices != [ ]) ''
          #   SUBSYSTEM=="net", ACTION=="add", ATTRS{vendor}=="0x${(lib.head config.ghaf.hardware.definition.network.pciDevices).vendorId}", ATTRS{device}=="0x${(lib.head config.ghaf.hardware.definition.network.pciDevices).productId}", NAME="${(lib.head config.ghaf.hardware.definition.network.pciDevices).name}"
          # '';

          microvm = {
            # Optimize is disabled because when it is enabled, qemu is built without libusb
            optimize.enable = false;
            vcpu = 4;
            mem = 4096;
            hypervisor = "qemu";   
            kernelParams = [ "loglevel=7 debug clk_ignore_unused pd_ignore_unused log_buf_len=128M" ];

            shares =
              [
                {
                  tag = "ro-store";
                  source = "/nix/store";
                  mountPoint = "/nix/.ro-store";
                  proto = "virtiofs";
                }
              ]
              ++ lib.optionals isGuiVmEnabled [
                {
                  # Add the waypipe-ssh public key to the microvm
                  tag = config.ghaf.security.sshKeys.waypipeSshPublicKeyName;
                  source = config.ghaf.security.sshKeys.waypipeSshPublicKeyDir;
                  mountPoint = config.ghaf.security.sshKeys.waypipeSshPublicKeyDir;
                  proto = "virtiofs";
                }
              ];

            writableStoreOverlay = lib.mkIf config.ghaf.development.debug.tools.enable "/nix/.rw-store";
            qemu = {
              machine =
                {
                  # Use the same machine type as the host
                  x86_64-linux = "q35";
                  aarch64-linux = "virt";
                }
                .${config.nixpkgs.hostPlatform.system};
              extraArgs = [
                "-device"
                "qemu-xhci"
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
            };
          };

          fileSystems = lib.mkIf isGuiVmEnabled {
            ${config.ghaf.security.sshKeys.waypipeSshPublicKeyDir}.options = [ "ro" ];
          };

          # SSH is very picky about to file permissions and ownership and will
          # accept neither direct path inside /nix/store or symlink that points
          # there. Therefore we copy the file to /etc/ssh/get-auth-keys (by
          # setting mode), instead of symlinking it.
          environment.etc = lib.mkIf isGuiVmEnabled {
            ${config.ghaf.security.sshKeys.getAuthKeysFilePathInEtc} = sshKeysHelper.getAuthKeysSource;
          };
        }
      )
    ];
  };
  cfg = config.ghaf.virtualization.microvm.gpuvm;
in
{
  options.ghaf.virtualization.microvm.gpuvm = {
    enable = lib.mkEnableOption "gpuvm";

    extraModules = lib.mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        gpuvm's NixOS configuration.
      '';
      default = [ ];
    };
  };

  config = lib.mkIf cfg.enable {
    services.udev.extraRules = ''
      # Allow group kvm to all devices that are binded to vfio 
      SUBSYSTEM=="vfio",GROUP="kvm"
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

    # Apply the device tree overlay only to tegra234-p3701-host-passthrough.dtb
    hardware.deviceTree.overlays = [
      {
        name = "GPU/Display passthrough overlay to host DTB";
        dtsFile = ./gpu_passthrough_overlay.dts;
      }
    ];

    microvm.vms."${vmName}" = {
      autostart = true;
      restartIfChanged = false;
      config = gpuvmBaseConfiguration // {
        imports = gpuvmBaseConfiguration.imports ++ cfg.extraModules;
        
        boot = {
          kernelPackages = config.boot.kernelPackages;
          extraModulePackages = [nvidia-oot];
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
              patch = ./0001-tegra-fixed-chip-id.patch;
            }
          ];
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
