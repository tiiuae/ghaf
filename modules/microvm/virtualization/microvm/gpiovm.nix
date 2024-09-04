# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}: with pkgs;
let
  configHost = config;
  vmName = "gpio-vm";
  macAddress = "03:00:00:07:06:05";

  isGuiVmEnabled = config.ghaf.virtualization.microvm.guivm.enable;

  sshKeysHelper = pkgs.callPackage ../../../../packages/ssh-keys-helper {
    inherit pkgs;
    inherit config;
  };

  kernelPath = "${config.system.build.kernel}";
  guestKernel = "${kernelPath}/Image"; # the host's kernel image can be used in the guest

  dtsName = "qemu-gpio-guestvm.dts";
  dtbName = "qemu-gpio-guestvm.dtb";

  # Build the guest specific DTB file for GPIO passthrough
  gpioDtbDerivation = builtins.trace "Creating guest DTB" pkgs.stdenv.mkDerivation {
    pname = "gpio-vm-dtb";
    version = "1.0";

    src = ./dtb;
    buildInputs = [ pkgs.dtc ];

    # unpackPhase = ''
    #   mkdir -p ${kernelPath}/dtbs
    #   cp ${dtsName} ${kernelPath}/dtbs/
    # '';

    buildPhase = ''
      mkdir -p $out
      # ls -thog $src
      dtc -I dts -O dtb -o $out/${dtbName} $src/${dtsName}
      # ls -thog $out
    '';

    installPhase = ''
      # cp $src/${dtsName} ${kernelPath}/dtbs/
      # cp $out/${dtbName} ${kernelPath}/dtbs/
    '';
   
    outputs = [ "out" ];
  };

  gpioGuestDtb = "${gpioDtbDerivation}/${dtbName}";

  /*
  guestRootFsName = "gpiovm_rootfs.qcow2";   # a non-ghaf temporary fs for debugging
  # Create the guest rootfs qcow2 file (not a ghaf fs -- temporary)
  gpioGuestFsDerivation = builtins.trace "Creating guest rootfs" pkgs.stdenv.mkDerivation {
    pname = "gpio-guest-fs";
    version = "1.0";

    buildInputs = [ pkgs.bzip2 ];

    src = ./qcow2;
    
    buildPhase = ''
      echo buildPhase
      # ls -thog $src

      mkdir -p $out 
      if [ -f $src/${guestRootFsName}.x00 ]
        then
          echo "split qcow2 in source"
          cat $src/${guestRootFsName}.x* >> $out/${guestRootFsName}
        else if [ -f $src/${guestRootFsName}.bzip2.x00 ]
          then 
            echo "split bzip2 in source"
            cat $src/${guestRootFsName}.bzip2.x* | \
            bunzip2 -dc > $out/${guestRootFsName}
          fi  
        fi
      echo "target created"
    '';

    installPhase = ''
    '';

    rootFs = "$out/${guestRootFsName}";
    # outputs = [ "rootFs" ];
    outputs = [ "out" ];
  };

  guestRootFs = "${gpioGuestFsDerivation}/${guestRootFsName}";
  */

  gpiovmBaseConfiguration = {
    imports = [
      inputs.impermanence.nixosModules.impermanence
      inputs.self.nixosModules.givc-gpiovm
      /*
      (import ./common/vm-networking.nix {
        inherit
          config
          lib
          vmName
          macAddress
          ;
        internalIP = 1;
        isGateway = true;
      })
      */

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
              #       that has been passed through to gpiovm
              # ssh.daemon.enable = lib.mkDefault config.ghaf.development.ssh.daemon.enable;
              debug.tools.enable = lib.mkDefault config.ghaf.development.debug.tools.enable;
              nix-setup.enable = lib.mkDefault config.ghaf.development.nix-setup.enable;
            };
            systemd = {
              enable = true;
              withName = "gpiovm-systemd";
              withAudit = config.ghaf.profiles.debug.enable;
              withPolkit = true;
              # withResolved = true;
              # withTimesyncd = true;
              withDebug = config.ghaf.profiles.debug.enable;
              withHardenedConfigs = true;
            };
            givc.gpiovm.enable = true;
            # Logging client configuration
            logging.client.enable = config.ghaf.logging.client.enable;
            logging.client.endpoint = config.ghaf.logging.client.endpoint;
            storagevm = {
              enable = true;
              name = "gpiovm";
              directories = [ "/etc/NetworkManager/system-connections/" ];
            };
          };

          time.timeZone = config.time.timeZone;
          system.stateVersion = lib.trivial.release;

          nixpkgs = {
            buildPlatform.system = config.nixpkgs.buildPlatform.system;
            hostPlatform.system = config.nixpkgs.hostPlatform.system;
          };
          
          /*
          networking = {
            firewall.allowedTCPPorts = [ 53 ];
            firewall.allowedUDPPorts = [ 53 ];
          };
          */

          #services.openssh = config.ghaf.security.sshKeys.sshAuthorizedKeysCommand;
          # WORKAROUND: Create a rule to temporary hardcode device name for Wi-Fi adapter on x86
          # TODO this is a dirty hack to guard against adding this to Nvidia/vm targets which
          /*
          # dont have that definition structure yet defined. FIXME.
          # TODO the hardware.definition should not even be exposed in targets that do not consume it
          services.udev.extraRules = lib.mkIf (config.ghaf.hardware.definition.network.pciDevices != [ ]) ''
            SUBSYSTEM=="net", ACTION=="add", ATTRS{vendor}=="0x${(lib.head config.ghaf.hardware.definition.network.pciDevices).vendorId}", ATTRS{device}=="0x${(lib.head config.ghaf.hardware.definition.network.pciDevices).productId}", NAME="${(lib.head config.ghaf.hardware.definition.network.pciDevices).name}"
          '';
          */
          microvm = {
            optimize.enable = true;
            hypervisor = "qemu";
            shares =
              [
                {
                  tag = "ro-store";
                  source = "/nix/store";
                  mountPoint = "/nix/.ro-store";
                }
              ]
              ++ lib.optionals isGuiVmEnabled [
                /*
                {
                  # Add the waypipe-ssh public key to the microvm
                  tag = config.ghaf.security.sshKeys.waypipeSshPublicKeyName;
                  source = config.ghaf.security.sshKeys.waypipeSshPublicKeyDir;
                  mountPoint = config.ghaf.security.sshKeys.waypipeSshPublicKeyDir;
                }
                */
              ];

            writableStoreOverlay = lib.mkIf config.ghaf.development.debug.tools.enable "/nix/.rw-store";

            # mem = 2024;
            # mem = 512;
            kernel = config.boot.kernelPackages.kernel;   # default would do
            cpu = "host";
            kernelParams = [
              "rootwait"
              "root=/dev/vda"
              "-dtb ${gpioGuestDtb}"       # can this read host's FS?
            ];
            graphics.enable = false;
            qemu = {
            # qemu = builtins.trace "Qemu params, filenames: ${dtsName}, ${dtbName}, ${guestKernel}, ${guestRootFsName}" {
              machine =
                {
                  # Use the same machine type as the host
                  x86_64-linux = "q35";
                  aarch64-linux = "virt";
                }
                .${config.nixpkgs.hostPlatform.system};
              serialConsole = true;
              extraArgs = lib.mkForce [
                "-sandbox" "on"
                "-nographic"
                "-no-reboot"
                # "-dtb ${gpioGuestDtb}"
                # "-kernel" "${guestKernel}"
                # "-drive" "file=${guestRootFs},if=virtio,format=qcow2"
                # "-machine" "virt,accel=kvm"
                #"-cpu" "host"
                # "-m" "2G"
                # "-smp" "2"
                # "-serial" "pty"
                # "-net" "user,hostfwd=tcp::2222-:22"
                # "-net" "nic"
              ];
            };
          };

          /*
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
          */
        }
      )
    ];
  };
  cfg = config.ghaf.virtualization.microvm.gpiovm;
in
{
  options.ghaf.virtualization.microvm.gpiovm = {
    enable = lib.mkEnableOption "GpioVM";

    # also declared in agx-gpiovm-passthrough.nix
    extraModules = builtins.trace "GpioVM: Evaluating extraModules in gpiovm.nix" lib.mkOption {
      description = ''
        List of additional modules to be imported and evaluated as part of
        GpioVM's NixOS configuration.
      '';
      # A service that runs a script to test gpio pins
      # default = [ import ./gpio-test.nix { pkgs = pkgs; } ];
    };
  };

  config = lib.mkIf cfg.enable {
    microvm.vms."${vmName}" = {
      autostart = false;
      config =
        gpiovmBaseConfiguration
        // {
          imports =
            gpiovmBaseConfiguration.imports
            ++ cfg.extraModules;
        };
      # specialArgs = {inherit lib;};
    };
  };
}
